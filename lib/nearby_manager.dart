import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adhoc_cache/connected_device.dart';
import 'package:adhoc_cache/playlist_item.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nearby_plugin/nearby_plugin.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';

class AdhocManager extends ChangeNotifier {
  static MethodChannel platform =
      const MethodChannel('adhoc.music.player/main');

  final _uuid = const Uuid().v4();

  final TransferManager _manager = TransferManager(NearbyStrategy.P2P_STAR);
  final List<ConnectedDevice> _discovered = List.empty(growable: true);
  final List<ConnectedDevice> _peers = List.empty(growable: true);
  final List<PlaylistItem> _playlist = List.empty(growable: true);
  final HashMap<String, HashMap<String, PlatformFile?>> _globalPlaylist =
      HashMap();
  final HashMap<String, PlatformFile?> _localPlaylist = HashMap();
  final HashMap<String, bool> _isTransfering = HashMap();
  final Set<String> timestamps = <String>{};

  bool requested = false;
  bool display = false;
  String? selected = NONE;

  AdhocManager() {
    _manager.enable("");
    _manager.eventStream.listen(_processAdHocEvent);
  }

  // Adhoc functions

  void discover() {
    _manager.discovery(3600);
  }

  void connect(ConnectedDevice device) async {
    _manager.connect(device.address!);
    _discovered.removeWhere((element) => (element.address == device.address));
    notifyListeners();
  }

  void _processAdHocEvent(NearbyMessage event) {
    switch (event.type) {
      case NearbyMessageType.onEndpointDiscovered:
        var endpoint =
            ConnectedDevice(label: event.endpoint, address: event.endpointId);
        // Check for duplicate
        var duplicate =
            _discovered.firstWhereOrNull((e) => endpoint.address == e.address);
        if (duplicate == null) {
          _discovered.add(endpoint);
          notifyListeners();
        }
        break;
      case NearbyMessageType.onEndpointLost:
        _discovered.removeWhere((e) => e.address == event.endpointId);
        notifyListeners();
        break;
      case NearbyMessageType.onDiscoveryEnded:
        break;
      case NearbyMessageType.onPayloadReceived:
        _processDataReceived(event);
        break;
      case NearbyMessageType.onPayloadTransferred:
        break;
      case NearbyMessageType.onConnectionAccepted:
        _discovered.removeWhere((e) => e.address == event.endpointId);
        _peers.add(
            ConnectedDevice(label: event.endpoint, address: event.endpointId));
        notifyListeners();
        break;
      case NearbyMessageType.onConnectionEnded:
      case NearbyMessageType.onConnectionRejected:
        _peers.removeWhere((e) => e.address == event.endpointId);
        break;
      default:
    }
  }

  Future<void> _processDataReceived(NearbyMessage event) async {
    var peer =
        ConnectedDevice(label: event.endpoint, address: event.endpointId);
    var data = jsonDecode(jsonDecode(jsonEncode(event.payload))) as Map;

    switch (data['type'] as int) {
      case PLAYLIST:
        var peers = data['peers'] as List;
        var songs = data['songs'] as List;
        var timestamp = data['timestamp'] as String;
        if (timestamps.contains(timestamp)) {
          break;
        } else {
          timestamps.add(timestamp);
        }

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
          if (!_playlist.contains(pair)) {
            _playlist.add(pair);
          }
        }

        _globalPlaylist[peerUuid] = entry;

        notifyListeners();
        _manager.broadcastExcept(jsonEncode(data), [peer.address!]);
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
          _manager.sendPayload(jsonEncode(message), peer.address!);

          message.clear();

          message.putIfAbsent('type', () => REPLY);
          message.putIfAbsent('name', () => name);
          message.putIfAbsent('song', () => bytes);
          message.putIfAbsent('uuid', () => _uuid);
          _manager.sendPayload(jsonEncode(message), peer.address!);
        }

        break;

      case REPLY:
        var name = data['name'] as String;
        var song =
            Uint8List.fromList((data['song'] as List<dynamic>).cast<int>());

        var tempDir = await getTemporaryDirectory();
        var tempFile = File('${tempDir.path}/$name');
        await tempFile.writeAsBytes(song, flush: true);

        var entry = HashMap<String, PlatformFile>();
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
        if (!_playlist.contains(pair)) {
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
      peers.add(peer);
      song.forEach((key, value) {
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
    message.putIfAbsent('timestamp', () => DateTime.now().toIso8601String());
    _manager.broadcast(jsonEncode(message));
  }

  void switchView() {
    display = !display;
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
            _manager.broadcast(jsonEncode(message));

            requested = true;
            notifyListeners();
            _isTransfering.putIfAbsent(selected!, () => false);

            Timer(const Duration(seconds: 30), () {
              if (requested == true && _isTransfering[selected] == false) {
                _manager.sendPayload(jsonEncode(message), peerName);
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

  List<ConnectedDevice> get discovered => _discovered;
  List<ConnectedDevice> get peers => _peers;
  List<PlaylistItem> get playlist => _playlist;
  HashMap<String, PlatformFile?> get localPlaylist => _localPlaylist;
}
