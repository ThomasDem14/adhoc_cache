import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:adhoc_cache/connected_device.dart';
import 'package:adhoc_cache/musicarchive/music_downloader.dart';
import 'package:adhoc_cache/playlist_item.dart';
import 'package:adhoc_plugin/adhoc_plugin.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';

class AdhocManager extends ChangeNotifier {
  static MethodChannel platform =
      const MethodChannel('adhoc.music.player/main');

  final _uuid = const Uuid().v4();

  final TransferManager _manager = TransferManager(true);

  final List<AdHocDevice> _discovered = List.empty(growable: true);
  final List<ConnectedDevice> _discoveredFormatted = List.empty(growable: true);
  final List<ConnectedDevice> _peers = List.empty(growable: true);

  // Pair source x filename
  final List<PlaylistItem> _playlist = List.empty(growable: true);
  final HashMap<String, HashMap<String, PlatformFile?>> _globalPlaylist =
      HashMap();
  // Name of the song => file
  final HashMap<String, PlatformFile?> _localPlaylist = HashMap();

  final HashMap<String, bool> _isTransfering = HashMap();

  bool requested = false;
  int display = 0;
  String? selected = NONE;

  final MusicDownloader _musicDownloader = MusicDownloader();
  bool displaySongs = false;
  List<Song> availableSongs = List.empty(growable: true);

  AdhocManager() {
    _manager.enable();
    _manager.eventStream.listen(_processAdHocEvent);
    _manager.open = true;
  }

  // Adhoc functions

  void discover() {
    _manager.discovery();
  }

  void connect(ConnectedDevice device) async {
    var adhocDevice =
        _discovered.firstWhere((e) => device.address == _macFromAdhocDevice(e));

    await _manager.connect(adhocDevice);

    _discovered.removeWhere((e) => (e.mac == adhocDevice.mac));
    _discoveredFormatted.removeWhere((e) => (e.address == device.address));
    notifyListeners();
  }

  void _processAdHocEvent(Event event) {
    switch (event.type) {
      case AdHocType.onDeviceDiscovered:
        var endpoint = ConnectedDevice(
            label: event.device!.name,
            address: _macFromAdhocDevice(event.device!));
        // Check for duplicate
        var duplicate =
            _discovered.firstWhereOrNull((e) => endpoint.address == e.address);
        if (duplicate == null) {
          _discoveredFormatted.add(endpoint);
          _discovered.add(event.device!);
          notifyListeners();
        }
        break;
      case AdHocType.onDataReceived:
        _processDataReceived(event);
        break;
      case AdHocType.onForwardData:
        _processDataReceived(event);
        break;
      case AdHocType.onConnection:
        _discovered.removeWhere((e) => e.mac == event.device!.mac);
        _discoveredFormatted.removeWhere(
            (e) => e.address == _macFromAdhocDevice(event.device!));
        _peers.add(ConnectedDevice(
            label: event.device!.name,
            address: _macFromAdhocDevice(event.device!)));
        notifyListeners();
        break;
      case AdHocType.onConnectionClosed:
        _peers.removeWhere((device) => device.address == event.device!.address);
        notifyListeners();
        break;
      default:
    }
  }

  Future<void> _processDataReceived(Event event) async {
    var peer = event.device;
    var data = event.data as Map;

    switch (data['type'] as int) {
      case PLAYLIST:
        var peers = data['peers'] as List;
        var songs = data['songs'] as List;

        var peerUuid = peers.first as String;
        var entry = _globalPlaylist[peerUuid] ?? HashMap();

        for (var i = 0; i < peers.length; i++) {
          if (peerUuid == peers[i]) {
            entry.putIfAbsent(songs[i] as String,
                () => PlatformFile(name: songs[i] as String, size: 0));
          } else {
            _globalPlaylist[peerUuid] = entry;

            peerUuid = peers[i] as String;
            entry = _globalPlaylist[peerUuid] ?? HashMap();

            entry.putIfAbsent(songs[i] as String,
                () => PlatformFile(name: songs[i] as String, size: 0));
          }

          var pair = PlaylistItem(source: peerUuid, title: songs[i] as String);
          var duplicate =
              _playlist.firstWhereOrNull((e) => e.title == pair.title);
          if (duplicate == null) {
            _playlist.add(pair);
          }
        }

        _globalPlaylist[peerUuid] = entry;

        notifyListeners();
        _manager.broadcastExcept(data, peer!);
        break;

      case REQUEST:
        var name = data['name'] as String;
        var found = false;
        Uint8List? bytes;
        PlatformFile? file;

        if (_localPlaylist.containsKey(name)) {
          found = true;
          bytes = _localPlaylist[name]!.bytes!;
        } else {
          for (final entry in _globalPlaylist.entries) {
            var _playlist = entry.value;
            if (_playlist.containsKey(name)) {
              file = _playlist[name];
              if (file == null && file!.bytes == null) {
                found = false;
                break;
              } else {
                bytes = file.bytes;
                if (bytes != null) {
                  found = true;
                } else {
                  found = false;
                }
                break;
              }
            }
          }
        }

        if (found == false) {
          break;
        } else {
          var message = HashMap<String, dynamic>();
          message = HashMap<String, dynamic>();
          message.putIfAbsent('type', () => TRANSFER);
          message.putIfAbsent('name', () => name);
          _manager.sendMessageTo(message, peer!.label!);

          message.clear();

          message.putIfAbsent('type', () => REPLY);
          message.putIfAbsent('name', () => name);
          message.putIfAbsent('song', () => bytes);
          message.putIfAbsent('uuid', () => _uuid);
          _manager.sendMessageTo(message, peer.label!);
        }

        break;

      case REPLY:
        var name = data['name'] as String;
        var song =
            Uint8List.fromList((data['song'] as List<dynamic>).cast<int>());

        var tempDir = await getTemporaryDirectory();
        var tempFile = File('${tempDir.path}/$name');
        await tempFile.writeAsBytes(song, flush: true);

        var entry =
            _globalPlaylist[data['uuid']] ?? HashMap<String, PlatformFile>();
        entry.putIfAbsent(
            name,
            () => PlatformFile(
                bytes: song,
                name: name,
                path: tempFile.path,
                size: song.length));

        _globalPlaylist.update(data['uuid'], (value) => entry,
            ifAbsent: () => entry);
        requested = false;
        notifyListeners();
        break;

      case TRANSFER:
        var name = data['name'] as String;
        _isTransfering.update(name, (value) => true, ifAbsent: () => true);
        break;

      default:
    }
  }

  // Playlist management

  Future<void> openFileExplorer() async {
    var result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
    );

    if (result != null) {
      for (var file in result.files) {
        var bytes = await File(file.path!).readAsBytes();
        var song = PlatformFile(
          name: file.name,
          path: file.path,
          bytes: bytes,
          size: bytes.length,
        );

        _localPlaylist.putIfAbsent(file.name, () => song);
        var pair = PlaylistItem(source: _uuid, title: file.name);
        var duplicate =
            _playlist.firstWhereOrNull((e) => e.title == pair.title);
        if (duplicate == null) {
          _playlist.add(pair);
        }
      }
    }

    _updatePlaylist();
  }

  void _updatePlaylist() async {
    var peers = List<String>.empty(growable: true);
    var songs = List<String>.empty(growable: true);

    _globalPlaylist.forEach((peer, song) {
      song.forEach((key, value) {
        peers.add(peer);
        songs.add(key);
      });
    });

    _localPlaylist.forEach((name, file) {
      peers.add(_uuid);
      songs.add(name);
    });

    notifyListeners();

    var message = HashMap<String, dynamic>();
    message.putIfAbsent('type', () => PLAYLIST);
    message.putIfAbsent('peers', () => peers);
    message.putIfAbsent('songs', () => songs);
    _manager.broadcast(message);
  }

  List<MusicCategories> getCategories() {
    return _musicDownloader.getCategories();
  }

  void displaySongsByCategory(MusicCategories category) async {
    availableSongs = await _musicDownloader.getByCategory(category);
    displaySongs = true;
    notifyListeners();
  }

  Future<void> downloadSong(Song song) async {
    var songBytes = await _musicDownloader.downloadSong(song);

    var tempDir = await getTemporaryDirectory();
    var tempFile = File('${tempDir.path}/${song.title}');
    await tempFile.writeAsBytes(songBytes, flush: true);

    var file = PlatformFile(
      name: song.title,
      path: tempFile.path,
      bytes: songBytes,
      size: songBytes.length,
    );

    _localPlaylist.putIfAbsent(file.name, () => file);
    var pair = PlaylistItem(source: _uuid, title: file.name);
    var duplicate = _playlist.firstWhereOrNull((e) => e.title == pair.title);
    if (duplicate == null) {
      _playlist.add(pair);
    }

    _updatePlaylist();
  }

  void screenConnections() {
    display = 0;
    displaySongs = false;
    notifyListeners();
  }

  void screenPlaylist() {
    displaySongs = false;
    display = 1;
    notifyListeners();
  }

  void screenDownload() {
    displaySongs = false;
    display = 2;
    notifyListeners();
  }

  void setSelected(String data) {
    selected = data;
    notifyListeners();
  }

  void play() {
    if (selected!.compareTo(NONE) == 0) {
      return;
    }

    PlatformFile? file;
    if (_localPlaylist.containsKey(selected)) {
      file = _localPlaylist[selected];
    } else {
      _globalPlaylist.forEach((peerName, playlist) {
        if (playlist.containsKey(selected)) {
          file = playlist[selected];
          if (file == null || file!.size == 0) {
            var message = HashMap<String, dynamic>();
            message.putIfAbsent('type', () => REQUEST);
            message.putIfAbsent('name', () => selected);
            _manager.broadcast(message);

            requested = true;
            notifyListeners();
            _isTransfering.putIfAbsent(selected!, () => false);

            Timer(const Duration(seconds: 30), () {
              if (requested == true && _isTransfering[selected] == false) {
                _manager.sendMessageTo(message, peerName);
              }
            });
          }
        }
      });
    }

    if (requested == false) {
      platform.invokeMethod('play', file!.path);
    }
  }

  void pause() {
    if (selected!.compareTo(NONE) == 0) {
      return;
    }

    platform.invokeMethod('pause');
  }

  void stop() {
    if (selected!.compareTo(NONE) == 0) {
      return;
    }

    selected = NONE;
    platform.invokeMethod('stop');

    notifyListeners();
  }

  // Getters

  List<ConnectedDevice> get discovered => _discoveredFormatted;
  List<ConnectedDevice> get peers => _peers;
  List<PlaylistItem> get playlist => _playlist;

  // Others

  String _macFromAdhocDevice(AdHocDevice device) {
    return device.mac.ble == '' ? device.mac.wifi : device.mac.ble;
  }
}
