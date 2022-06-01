import 'package:adhoc_cache/nearby_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants.dart';

class MainPage extends StatelessWidget {
  const MainPage({Key? key}) : super(key: key);

  Widget downloadSongPage(BuildContext context) {
    return Consumer<AdhocManager>(builder: ((context, manager, child) {
      if (manager.displaySongs) {
        var songs = manager.availableSongs;
        return Column(children: [
          const Center(child: Text('Choose a song')),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: ((context, index) => Card(
                    child: ListTile(
                      title: Center(child: Text(songs[index].title)),
                      subtitle: Center(child: Text(songs[index].artist)),
                      onTap: () {
                        manager.downloadSong(songs[index]);
                        manager.screenPlaylist();
                      },
                    ),
                  )),
            ),
          ),
        ]);
      }

      var categories = manager.getCategories();
      return Column(children: [
        const Center(child: Text('Choose a category')),
        Expanded(
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: ((context, index) => Card(
                  child: ListTile(
                    title: Center(child: Text(categories[index].name)),
                    onTap: () =>
                        manager.displaySongsByCategory(categories[index]),
                  ),
                )),
          ),
        ),
      ]);
    }));
  }

  Widget adhocPage(BuildContext context) {
    return Consumer<AdhocManager>(
      builder: (context, manager, child) => Column(children: [
        const Card(child: ListTile(title: Center(child: Text('Ad Hoc Peers')))),
        ElevatedButton(
          child: const Center(child: Text('Search for nearby devices')),
          onPressed: manager.discover,
        ),
        const Card(
            child: ListTile(title: Center(child: Text('Discovered devices')))),
        Expanded(
          child: ListView(
            children: manager.discovered.map((device) {
              return Card(
                child: ListTile(
                  title: Center(child: Text(device.label!)),
                  subtitle: Center(child: Text(device.address!)),
                  onTap: () async {
                    manager.connect(device);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const Card(
            child: ListTile(title: Center(child: Text('Connected devices')))),
        Expanded(
          child: ListView(
            children: manager.peers.map((device) {
              return Card(
                child: ListTile(
                  title: Center(child: Text(device.label!)),
                  subtitle: Center(child: Text(device.address!)),
                  onTap: () async {
                    manager.connect(device);
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget playlistPage(BuildContext context) {
    return Consumer<AdhocManager>(
      builder: (context, manager, child) => Column(
        children: [
          Card(
              child: Stack(
            children: <Widget>[
              ListTile(
                title: Center(child: Text('${manager.selected}')),
                subtitle: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.play_arrow_rounded),
                      onPressed: manager.play,
                    ),
                    IconButton(
                      icon: const Icon(Icons.pause_rounded),
                      onPressed: manager.pause,
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop_rounded),
                      onPressed: manager.stop,
                    ),
                    if (manager.requested)
                      const Center(child: CircularProgressIndicator())
                    else
                      Container()
                  ],
                ),
              ),
            ],
          )),
          const Card(
            color: Colors.blue,
            child: ListTile(
              title: Center(
                child: Text('Ad Hoc Playlist',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: manager.playlist.map((pair) {
                return Card(
                  child: ListTile(
                    title: Center(child: Text(pair.source!)),
                    subtitle: Center(child: Text(pair.title!)),
                    onTap: () => manager.setSelected(pair.title!),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text('Ad Hoc Music Client'),
            actions: <Widget>[
              PopupMenuButton<MenuOptions>(
                onSelected: (result) async {
                  switch (result) {
                    case MenuOptions.add:
                      await Provider.of<AdhocManager>(context, listen: false)
                          .openFileExplorer();
                      break;

                    case MenuOptions.connections:
                      Provider.of<AdhocManager>(context, listen: false)
                          .screenConnections();
                      break;

                    case MenuOptions.playlist:
                      Provider.of<AdhocManager>(context, listen: false)
                          .screenPlaylist();
                      break;

                    case MenuOptions.download:
                      Provider.of<AdhocManager>(context, listen: false)
                          .screenDownload();
                      break;
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<MenuOptions>>[
                  const PopupMenuItem<MenuOptions>(
                    value: MenuOptions.add,
                    child: ListTile(
                      leading: Icon(Icons.playlist_add),
                      title: Text('Add song to playlist'),
                    ),
                  ),
                  const PopupMenuItem<MenuOptions>(
                    value: MenuOptions.download,
                    child: ListTile(
                      leading: Icon(Icons.download),
                      title: Text('Download song'),
                    ),
                  ),
                  const PopupMenuItem<MenuOptions>(
                    value: MenuOptions.playlist,
                    child: ListTile(
                      leading: Icon(Icons.music_note),
                      title: Text('View playlist'),
                    ),
                  ),
                  const PopupMenuItem<MenuOptions>(
                    value: MenuOptions.connections,
                    child: ListTile(
                      leading: Icon(Icons.person),
                      title: Text('View connections'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Consumer<AdhocManager>(
            builder: (_, manager, child) {
              switch (manager.display) {
                case 1:
                  return playlistPage(context);
                case 2:
                  return downloadSongPage(context);
                default:
                  return adhocPage(context);
              }
            },
          ),
        ),
      ),
    );
  }
}
