import 'package:adhoc_cache/adhoc_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'search_bar.dart';

class MainPage extends StatelessWidget {
  const MainPage({Key? key}) : super(key: key);

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

                    case MenuOptions.search:
                      var songs = List<String>.empty(growable: true);
                      Provider.of<AdhocManager>(context, listen: false)
                          .localPlaylist
                          .entries
                          .map((entry) => songs.add(entry.key));

                      Provider.of<AdhocManager>(context, listen: false).selected =
                          (await showSearch(
                                context: context,
                                delegate: SearchBar(songs),
                              )) ??
                              NONE;
                      break;

                    case MenuOptions.display:
                      Provider.of<AdhocManager>(context, listen: false)
                          .switchView();
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
                    value: MenuOptions.search,
                    child: ListTile(
                      leading: Icon(Icons.search),
                      title: Text('Search song'),
                    ),
                  ),
                  const PopupMenuItem<MenuOptions>(
                    value: MenuOptions.display,
                    child: ListTile(
                      leading: Icon(Icons.music_note),
                      title: Text('Switch view'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Consumer<AdhocManager>(
                builder: (context, manager, child) => Expanded(
                  child: Column(
                    children: <Widget>[
                      if (!manager.display) ...<Widget>[
                        const Card(
                            child: ListTile(
                                title: Center(child: Text('Ad Hoc Peers')))),
                        ElevatedButton(
                          child: const Center(
                              child: Text('Search for nearby devices')),
                          onPressed: manager.discover,
                        ),
                        const Card(
                            child: ListTile(
                                title:
                                    Center(child: Text('Discovered devices')))),
                        Expanded(
                          child: ListView(
                            children: manager.discovered.map((device) {
                              return Card(
                                child: ListTile(
                                  title: Center(child: Text(device.label!)),
                                  subtitle:
                                      Center(child: Text(device.address!)),
                                  onTap: () async {
                                    manager.connect(device);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const Card(
                            child: ListTile(
                                title:
                                    Center(child: Text('Connected devices')))),
                        Expanded(
                          child: ListView(
                            children: manager.peers.map((device) {
                              return Card(
                                child: ListTile(
                                  title: Center(child: Text(device.label!)),
                                  subtitle:
                                      Center(child: Text(device.address!)),
                                  onTap: () async {
                                    manager.connect(device);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ] else ...<Widget>[
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
                                    const Center(
                                        child: CircularProgressIndicator())
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
