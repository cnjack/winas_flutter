import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:draggable_scrollbar/draggable_scrollbar.dart';

import './delete.dart';
import './rename.dart';
import './search.dart';
import './fileRow.dart';
import './newFolder.dart';
import '../redux/redux.dart';
import '../common/loading.dart';
import '../common/cache.dart';
import './backupView.dart';

List<FileNavView> _fileNavViews = [
  FileNavView(
    icon: Icon(Icons.people, color: Colors.white),
    title: '共享空间',
    nav: 'public',
    color: Colors.orange,
    onTap: (context) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) {
              return Files(
                node: Node(
                  name: '共享空间',
                  tag: 'built-in',
                ),
              );
            },
          ),
        ),
  ),
  FileNavView(
    icon: Icon(Icons.refresh, color: Colors.white),
    title: '备份空间',
    nav: 'backup',
    color: Colors.blue,
    onTap: (context) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BackupView(),
          ),
        ),
  ),
  FileNavView(
    icon: Icon(Icons.swap_vert, color: Colors.white),
    title: '传输任务',
    nav: 'transfer',
    color: Colors.purple,
  ),
];

Widget _buildRow(
  BuildContext context,
  List<Entry> entries,
  int index,
  List actions,
  Function download,
  Select select,
) {
  final entry = entries[index];
  switch (entry.type) {
    case 'dirTitle':
      return TitleRow(isFirst: true, type: 'directory');
    case 'fileTitle':
      return TitleRow(isFirst: index == 0, type: 'file');
    case 'file':
      return FileRow(
        key: Key(entry.name + entry.uuid),
        type: 'file',
        onPress: () => download(entry),
        entry: entry,
        actions: actions,
        isGrid: false,
        select: select,
      );
    case 'directory':
      return FileRow(
        key: Key(entry.name + entry.uuid),
        type: 'directory',
        onPress: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  return Files(
                    node: Node(
                      name: entry.name,
                      driveUUID: entry.pdrv,
                      dirUUID: entry.uuid,
                      tag: 'dir',
                    ),
                  );
                },
              ),
            ),
        entry: entry,
        actions: actions,
        isGrid: false,
        select: select,
      );
  }
  return null;
}

Widget _buildGrid(
  BuildContext context,
  List<Entry> entries,
  int index,
  Node parentNode,
  List actions,
  Function download,
  Select select,
) {
  final entry = entries[index];
  switch (entry.type) {
    case 'file':
      return FileRow(
        key: Key(entry.name + entry.uuid),
        type: 'file',
        onPress: () => download(entry),
        entry: entry,
        actions: actions,
        isGrid: true,
        select: select,
      );
    case 'directory':
      return FileRow(
        key: Key(entry.name + entry.uuid),
        type: 'directory',
        onPress: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  return Files(
                    node: Node(
                      name: entry.name,
                      driveUUID: parentNode.driveUUID,
                      dirUUID: entry.uuid,
                      tag: 'dir',
                    ),
                  );
                },
              ),
            ),
        entry: entry,
        actions: actions,
        isGrid: true,
        select: select,
      );
  }
  return Container();
}

class Files extends StatefulWidget {
  Files({Key key, this.node}) : super(key: key);

  final Node node;
  @override
  _FilesState createState() => _FilesState(node);
}

class _FilesState extends State<Files> {
  _FilesState(this.node);

  final Node node;
  Node currentNode;
  bool loading = true;
  Error _error;
  List<Entry> entries = [];
  List<Entry> dirs = [];
  List<Entry> files = [];
  List<DirPath> paths = [];
  ScrollController myScrollController = ScrollController();

  /// get actions in menu
  Function actions;

  /// update Selection, and setState
  Select select;

  Future refresh(state) async {
    String driveUUID;
    String dirUUID;
    if (node.tag == 'home') {
      Drive homeDrive = state.drives
          .firstWhere((drive) => drive.tag == 'home', orElse: () => null);

      driveUUID = homeDrive?.uuid;
      dirUUID = driveUUID;
      currentNode = Node(
        name: '云盘',
        driveUUID: driveUUID,
        dirUUID: driveUUID,
        tag: 'home',
      );
    } else if (node.tag == 'dir') {
      driveUUID = node.driveUUID;
      dirUUID = node.dirUUID;
      currentNode = node;
    } else if (node.tag == 'built-in') {
      Drive homeDrive = state.drives
          .firstWhere((drive) => drive.tag == 'built-in', orElse: () => null);

      driveUUID = homeDrive?.uuid;
      dirUUID = driveUUID;
      currentNode = Node(
        name: '共享空间',
        driveUUID: driveUUID,
        dirUUID: driveUUID,
        tag: 'built-in',
      );
    }

    // request listNav
    var listNav;
    try {
      listNav = await state.apis
          .req('listNavDir', {'driveUUID': driveUUID, 'dirUUID': dirUUID});
      _error = null;
    } catch (error) {
      setState(() {
        loading = false;
        _error = error;
      });

      print(error);
      return null;
    }

    // assert(listNav.data is Map<String, List>);
    // mix currentNode's dirUUID, driveUUID
    List<Entry> rawEntries = List.from(listNav.data['entries']
        .map((entry) => Entry.mixNode(entry, currentNode)));
    List<DirPath> rawPath =
        List.from(listNav.data['path'].map((path) => DirPath.fromMap(path)));

    // sort by type
    rawEntries.sort((a, b) => a.type.compareTo(b.type));

    // insert FileNavView
    List<Entry> newEntries = [];
    List<Entry> newDirs = [];
    List<Entry> newFiles = [];

    if (rawEntries.length == 0) {
      print('empty entries or some error');
    } else if (rawEntries[0]?.type == 'directory') {
      int index = rawEntries.indexWhere((entry) => entry.type == 'file');
      if (index > -1) {
        newDirs = List.from(rawEntries.take(index));

        // filter entry.hash
        newFiles = List.from(
            rawEntries.skip(index).where((entry) => entry.hash != null));
      } else {
        newDirs = rawEntries;
      }
    } else if (rawEntries[0]?.type == 'file') {
      // filter entry.hash
      newFiles = List.from(rawEntries.where((entry) => entry.hash != null));
    } else {
      print('other entries!!!!');
    }
    newEntries.addAll(rawEntries);

    if (this.mounted) {
      // avoid calling setState after dispose()
      setState(() {
        entries = newEntries;
        dirs = newDirs;
        files = newFiles;
        paths = rawPath;
        loading = false;
        _error = null;
      });
    }
    return null;
  }

  void refreshAsync(state) {
    refresh(state).then((data) {
      print('refresh success');
    }).catchError((error) {
      print('refresh error');
      print(error); // TODO
    });
  }

  void _download(BuildContext ctx, Entry entry, AppState state) async {
    showLoading(
      barrierDismissible: false,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints.expand(),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
      context: ctx,
    );
    final cm = await CacheManager.getInstance();
    String entryPath = await cm.getTmpFile(entry, state);

    Navigator.pop(ctx);
    if (entryPath == null) {
      showSnackBar(ctx, '打开失败');
    } else {
      try {
        await OpenFile.open(entryPath);
      } catch (error) {
        print(error);
        showSnackBar(ctx, '没有打开该类型文件的应用');
      }
    }
  }

  @override
  void initState() {
    super.initState();

    select = Select(() => this.setState(() {}));

    actions = (state) => [
          {
            'icon': Icons.edit,
            'title': '重命名',
            'types': ['file', 'directory'],
            'action': (BuildContext ctx, Entry entry) {
              Navigator.pop(ctx);
              showDialog(
                context: ctx,
                builder: (BuildContext context) => RenameDialog(
                      entry: entry,
                      node: currentNode,
                    ),
              ).then((success) => refresh(state));
            },
          },
          {
            'icon': Icons.content_copy,
            'title': '复制到...',
            'types': ['file', 'directory'],
            'action': () => print('copy to'),
          },
          {
            'icon': Icons.forward,
            'title': '移动到...',
            'types': ['file', 'directory'],
            'action': () => print('move to'),
          },
          {
            'icon': Icons.file_download,
            'title': '下载到本地',
            'types': ['file'],
            'action': () => print('move to'),
          },
          {
            'icon': Icons.share,
            'title': '分享到共享空间',
            'types': node.tag == 'built-in' ? [] : ['file', 'directory'],
            'action': (BuildContext ctx, Entry entry) async {
              Navigator.pop(ctx);
              showLoading(
                barrierDismissible: false,
                builder: (ctx) {
                  return Container(
                    constraints: BoxConstraints.expand(),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
                context: this.context,
              );

              // get built-in public drive
              Drive publicDrive = state.drives.firstWhere(
                  (drive) => drive.tag == 'built-in',
                  orElse: () => null);

              String driveUUID = publicDrive?.uuid;

              var args = {
                'type': 'copy',
                'entries': [entry.name],
                'policies': {
                  'dir': ['rename', 'rename'],
                  'file': ['rename', 'rename']
                },
                'dst': {'drive': driveUUID, 'dir': driveUUID},
                'src': {
                  'drive': currentNode.driveUUID,
                  'dir': currentNode.dirUUID
                },
              };
              try {
                await state.apis.req('xcopy', args);
                Navigator.pop(this.context);
                showSnackBar(ctx, '分享成功');
              } catch (error) {
                Navigator.pop(this.context);
                showSnackBar(ctx, '分享失败');
              }
            },
          },
          {
            'icon': Icons.open_in_new,
            'title': '使用其它应用打开',
            'types': ['file'],
            'action': () => print('rename'),
          },
          {
            'icon': Icons.delete,
            'title': '删除',
            'types': ['file', 'directory'],
            'action': (BuildContext ctx, Entry entry) async {
              Navigator.pop(ctx);
              bool success = await showDialog(
                context: this.context,
                builder: (BuildContext context) =>
                    DeleteDialog(entries: [entry]),
              );

              if (success) {
                await refresh(state);
                showSnackBar(ctx, '删除成功');
              } else {
                showSnackBar(ctx, '删除失败');
              }
            },
          },
        ];
  }

  openSearch(context, state) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return Search(
            node: currentNode,
            actions: actions(state),
            download: _download,
          );
        },
      ),
    );
  }

  Widget searchBar(AppState state) {
    return Material(
      elevation: 2.0,
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 1,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => openSearch(this.context, state),
              child: Row(
                children: <Widget>[
                  Container(width: 16),
                  Icon(Icons.search),
                  Container(width: 32),
                  Text('搜索文件', style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.create_new_folder),
            onPressed: () => showDialog(
                  context: this.context,
                  builder: (BuildContext context) =>
                      NewFolder(node: currentNode),
                ).then((success) => success == true ? refresh(state) : null),
          ),
          StoreConnector<AppState, VoidCallback>(
            converter: (store) {
              return () => store.dispatch(UpdateConfigAction(
                    Config(gridView: !store.state.config.gridView),
                  ));
            },
            builder: (context, callback) {
              return IconButton(
                icon: Icon(state.config.gridView
                    ? Icons.view_list
                    : Icons.view_module),
                onPressed: callback,
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.more_horiz),
            onPressed: () => {},
          ),
        ],
      ),
    );
  }

  Widget dirTitle() {
    return SliverFixedExtentList(
      itemExtent: 48,
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return TitleRow(isFirst: true, type: 'directory');
        },
        childCount: dirs.length > 0 ? 1 : 0,
      ),
    );
  }

  Widget fileTitle() {
    return SliverFixedExtentList(
      itemExtent: 48,
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return TitleRow(isFirst: dirs.length == 0, type: 'file');
        },
        childCount: files.length > 0 ? 1 : 0,
      ),
    );
  }

  Widget dirGrid(state) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
        childAspectRatio: 4.0,
      ),
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return _buildGrid(
            context,
            dirs,
            index,
            currentNode,
            actions(state),
            (entry) => _download(context, entry, state),
            select,
          );
        },
        childCount: dirs.length,
      ),
    );
  }

  Widget dirRow(state) {
    return SliverFixedExtentList(
      itemExtent: 64,
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return _buildRow(
            context,
            dirs,
            index,
            actions(state),
            (entry) => _download(context, entry, state),
            select,
          );
        },
        childCount: dirs.length,
      ),
    );
  }

  Widget fileGrid(state) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
        childAspectRatio: 1.0,
      ),
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return _buildGrid(
            context,
            files,
            index,
            currentNode,
            actions(state),
            (entry) => _download(context, entry, state),
            select,
          );
        },
        childCount: files.length,
      ),
    );
  }

  Widget fileRow(state) {
    return SliverFixedExtentList(
      itemExtent: 64,
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return _buildRow(
            context,
            files,
            index,
            actions(state),
            (entry) => _download(context, entry, state),
            select,
          );
        },
        childCount: files.length,
      ),
    );
  }

  AppBar directoryViewAppBar(AppState state) {
    return AppBar(
      title: Text(
        node.name,
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.normal,
        ),
      ),
      brightness: Brightness.light,
      backgroundColor: Colors.white,
      elevation: 2.0,
      iconTheme: IconThemeData(color: Colors.black38),
      actions: [
        IconButton(
          icon: Icon(Icons.search),
          onPressed: () => {},
        ),
        IconButton(
          icon: Icon(Icons.create_new_folder),
          onPressed: () => showDialog(
                context: context,
                builder: (BuildContext context) => NewFolder(node: currentNode),
              ).then((success) => success ? refresh(state) : null),
        ),
        StoreConnector<AppState, VoidCallback>(
          converter: (store) {
            return () => store.dispatch(UpdateConfigAction(
                  Config(gridView: !store.state.config.gridView),
                ));
          },
          builder: (context, callback) {
            return IconButton(
              icon: Icon(
                  state.config.gridView ? Icons.view_list : Icons.view_module),
              onPressed: callback,
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.more_horiz),
          onPressed: () => {},
        ),
      ],
    );
  }

  AppBar homeViewAppBar(AppState state) {
    return AppBar(
      elevation: 2.0,
      brightness: Brightness.light,
      backgroundColor: Colors.white,
      titleSpacing: 0.0,
      iconTheme: IconThemeData(color: Colors.black38),
      title: Container(
        color: Colors.grey[200],
        child: Container(
          child: searchBar(state),
        ),
      ),
    );
  }

  AppBar selectAppBar(AppState state) {
    return AppBar(
      title: Text(
        '选择了${select.selectedEntry.length}项',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.normal,
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.close, color: Colors.white),
        onPressed: () => select.clearSelect(),
      ),
      brightness: Brightness.light,
      elevation: 2.0,
      iconTheme: IconThemeData(color: Colors.white),
      actions: <Widget>[
        IconButton(
          icon: Icon(Icons.forward),
          onPressed: () => {},
        ),
        Builder(builder: (ctx) {
          return IconButton(
            icon: Icon(Icons.file_download),
            onPressed: () {
              showSnackBar(ctx, '${select.selectedEntry.length}个项目加入下载列表');
              select.clearSelect();
            },
          );
        }),
        IconButton(
          icon: Icon(Icons.more_horiz),
          onPressed: () => {},
        ),
      ],
    );
  }

  Widget homeView() {
    return StoreConnector<AppState, AppState>(
      onInit: (store) => refreshAsync(store.state),
      onDispose: (store) => {},
      converter: (store) => store.state,
      builder: (context, state) {
        return Scaffold(
          appBar:
              select.selectMode() ? selectAppBar(state) : homeViewAppBar(state),
          body: SafeArea(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // File list
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: RefreshIndicator(
                    onRefresh: () => refresh(state),
                    child: _error != null
                        ? Center(
                            child: Text('出错啦！'),
                          )
                        : entries.length == 0 && !loading
                            ? Center(
                                child: Text('空文件夹'),
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: DraggableScrollbar.semicircle(
                                  controller: myScrollController,
                                  child: CustomScrollView(
                                    key: Key(entries.length.toString()),
                                    controller: myScrollController,
                                    physics: AlwaysScrollableScrollPhysics(),
                                    slivers: <Widget>[
                                      // file nav view
                                      SliverFixedExtentList(
                                        itemExtent: 96.0,
                                        delegate: SliverChildBuilderDelegate(
                                          (BuildContext context, int index) {
                                            return Container(
                                              color: Colors.grey[200],
                                              height: 96,
                                              child: Row(
                                                children: _fileNavViews
                                                    .map<Widget>((FileNavView
                                                            fileNavView) =>
                                                        fileNavView
                                                            .navButton(context))
                                                    .toList(),
                                              ),
                                            );
                                          },
                                          childCount: 1,
                                        ),
                                      ),
                                      // dir title
                                      dirTitle(),
                                      // dir Grid or Row view
                                      state.config.gridView
                                          ? dirGrid(state)
                                          : dirRow(state),
                                      // file title
                                      fileTitle(),
                                      // file Grid or Row view
                                      state.config.gridView
                                          ? fileGrid(state)
                                          : fileRow(state),
                                      SliverFixedExtentList(
                                        itemExtent: 24,
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => Container(),
                                          childCount: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                  ),
                ),

                // FileNav
                loading
                    ? Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          color: Colors.grey[200],
                          height: 96,
                          child: Row(
                            children: _fileNavViews
                                .map<Widget>((FileNavView fileNavView) =>
                                    fileNavView.navButton(context))
                                .toList(),
                          ),
                        ),
                      )
                    : Container(),

                // CircularProgressIndicator
                loading
                    ? Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Container(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget directoryView() {
    return StoreConnector<AppState, AppState>(
      onInit: (store) => refreshAsync(store.state),
      onDispose: (store) => {},
      converter: (store) => store.state,
      builder: (context, state) {
        return Scaffold(
          appBar: select.selectMode()
              ? selectAppBar(state)
              : directoryViewAppBar(state),
          body: loading
              ? Center(
                  child: CircularProgressIndicator(),
                )
              : Theme(
                  data: Theme.of(context).copyWith(primaryColor: Colors.teal),
                  child: RefreshIndicator(
                    onRefresh: () => refresh(state),
                    child: _error != null
                        ? Center(
                            child: Text('出错啦！'),
                          )
                        : entries.length == 0
                            ? Center(
                                child: Text('空文件夹'),
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: DraggableScrollbar.semicircle(
                                  controller: myScrollController,
                                  child: CustomScrollView(
                                    key: Key(entries.length.toString()),
                                    controller: myScrollController,
                                    physics: AlwaysScrollableScrollPhysics(),
                                    slivers: <Widget>[
                                      // dir title
                                      dirTitle(),
                                      // dir Grid or Row view
                                      state.config.gridView
                                          ? dirGrid(state)
                                          : dirRow(state),
                                      // file title
                                      fileTitle(),
                                      // file Grid or Row view
                                      state.config.gridView
                                          ? fileGrid(state)
                                          : fileRow(state),
                                      SliverFixedExtentList(
                                        itemExtent: 24,
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => Container(),
                                          childCount: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                  ),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (node.tag == 'home') return homeView();
    if (node.tag == 'dir' || node.tag == 'built-in') return directoryView();
    return Center(child: Text('Error !'));
  }
}
