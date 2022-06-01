import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum MusicCategories {
  Blues,
  Jazz,
  Rock,
  Pop,
}

class Song {
  String artist;
  String title;
  String url;

  Song(this.artist, this.title, this.url);
}

class MusicDownloader {
  List<MusicCategories> getCategories() {
    return MusicCategories.values;
  }

  List<String> getCategoryNames() {
    return MusicCategories.values.map((e) => e.name).toList();
  }

  Future<List<Song>> getByCategory(MusicCategories category) async {
    var url =
        "https://freemusicarchive.org/genre/${category.name}/?pageSize=20&page=1&sort=interest&d=0";
    var httpClient = HttpClient();
    var request = await httpClient.getUrl(Uri.parse(url));
    var response = await request.close();

    var stringData = await response.transform(utf8.decoder).join();
    RegExp dataRegex = RegExp(r"data-track-info='(.*)'");

    var matches = dataRegex.allMatches(stringData);
    var songs = List<Song>.empty(growable: true);
    for (var match in matches) {
      var map = jsonDecode(match.group(1)!) as Map;
      var fileUrl = map['fileUrl'].toString();
      var formattedUrl = fileUrl.replaceAll("\\", "");
      var song = Song(map['artistName'], map['title'], formattedUrl);
      songs.add(song);
    }

    return songs;
  }

  Future<Uint8List> downloadSong(Song song) async {
    var httpClient = HttpClient();
    print(song.url);
    var request = await httpClient.getUrl(Uri.parse(song.url));
    var response = await request.close();

    final completer = Completer<Uint8List>();
    List<int> representation = List.empty(growable: true);
    response.listen((event) {
      representation.addAll(event);
    }, onDone: () => completer.complete(Uint8List.fromList(representation)));

    return completer.future;
  }

  /* data-track-info='{"id":95976,
  "handle":"Holiday_03-12",
  "url":"https:\/\/freemusicarchive.org\/music\/Silence_Is_Sexy\/Modern_Antiques_instrumental\/Holiday_03-12\/",
  "title":"Holiday (instrumental)",
  "artistName":"Silence Is Sexy",
  "artistUrl":"https:\/\/freemusicarchive.org\/music\/Silence_Is_Sexy\/",
  "albumTitle":"Antique Instrumentals",
  "playbackUrl":"https:\/\/freemusicarchive.org\/track\/Holiday_03-12\/stream\/","downloadUrl":
  "https:\/\/freemusicarchive.org\/track\/Holiday_03-12\/download\/",
  "fileName":"Silence_Is_Sexy_-_01_-_Holiday_instrumental.mp3",
  "fileUrl":"https:\/\/files.freemusicarchive.org\/storage-freemusicarchive-org\/music\/ccCommunity\/Silence_Is_Sexy\/Antique_Instrumentals\/Silence_Is_Sexy_-_01_-_Holiday_instrumental.mp3"
  }'
  */
}
