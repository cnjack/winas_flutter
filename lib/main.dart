import 'dart:io';
import 'package:redux/redux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock/wakelock.dart';
import 'package:intl/intl_standalone.dart';
import 'package:redux_persist/redux_persist.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_umplus/flutter_umplus.dart';
import 'package:flutter_i18n/flutter_i18n_delegate.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import './login/login.dart';
import './redux/redux.dart';
import './transfer/manager.dart';
import './common/appConfig.dart';
import './login/stationList.dart';
import './nav/bottom_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// temporarily fix issue https://github.com/flutter/flutter/issues/42420
  SystemChannels.skia
      .invokeMethod<void>('Skia.setResourceCacheMaxBytes', 200 << 20);

  Directory root = await getApplicationDocumentsDirectory();
  String _rootDir = root.path;

  // init persistor
  final persistor = Persistor<AppState>(
    storage: FileStorage(File("$_rootDir/config_v1.json")),
    serializer: JsonSerializer<AppState>(AppState.fromJson),
  );

  // Load initial state
  AppState initialState;

  // initialState = await persistor.load();
  try {
    initialState = await persistor.load(); // AppState.initial(); //
  } catch (error) {
    // print('load initialState error: $error');
    initialState = AppState.initial();
  }
  if (initialState?.localUser?.uuid != null) {
    // init TransferManager, load TransferItem
    TransferManager.init(initialState.localUser.uuid, initialState)
        .catchError(print);
  }
  // Create Store with Persistor middleware
  final store = Store<AppState>(
    appReducer,
    initialState: initialState ?? AppState.initial(),
    middleware: [persistor.createMiddleware()],
  );

  // check if test or production mode
  try {
    await AppConfig.checkDev();
  } catch (e) {
    print('checkDev failed $e');
  }

  // check if is iPad
  try {
    if (Platform.isIOS) {
      await AppConfig.checkiPad();
    }
  } catch (e) {
    print('check iPad failed $e');
  }

  // get deviceUUID
  final deviceUUID = await AppConfig.getDeviceUUID();
  print('deviceUUID: $deviceUUID');

  // keep screen on
  Wakelock.enable().catchError(print);

  // umeng
  AppConfig.umeng = store?.state?.config?.umeng;
  if (AppConfig.umeng != false) {
    FlutterUmplus.init(
      Platform.isAndroid
          ? '5d81d3bc0cafb29b6b00089f'
          : '5d81f1a20cafb23f590005ab',
      channel: null,
      reportCrash: true,
      logEnable: true,
      encrypt: true,
    );
  }

  // init language
  String lan = store?.state?.config?.language;

  if (lan != 'en' && lan != 'zh') {
    // load system locale
    try {
      // fix bug in iOS 13, waiting for Platform.localeName to get value
      int waitCount = 0;
      while (waitCount < 10) {
        if (Platform.localeName != null) {
          break;
        }
        // print('Platform.localeName is null $waitCount');
        await Future.delayed(Duration(milliseconds: 50));
        waitCount += 1;
      }

      final String systemLocale = await findSystemLocale();
      final List<String> systemLocaleSplitted = systemLocale.split('_');
      lan = systemLocaleSplitted[0];
    } catch (e) {
      lan = 'zh';
    }
  }

  // only support `en` and `zh`, default is `zh`
  Locale locale = lan == 'en' ? Locale('en') : Locale('zh');

  final FlutterI18nDelegate flutterI18nDelegate = FlutterI18nDelegate(
    useCountryCode: false,
    fallbackFile: 'zh',
    path: 'assets/locales',
    defaultLocale: locale,
  );

  // preload to avoid black screen
  try {
    await flutterI18nDelegate.load(null);
  } catch (e) {
    print('flutterI18nDelegate load failed $e');
  }

  runApp(MyApp(initialState, store, flutterI18nDelegate));
}

class MyApp extends StatelessWidget {
  final Store<AppState> store;
  final AppState initialState;
  final FlutterI18nDelegate flutterI18nDelegate;

  MyApp(this.initialState, this.store, this.flutterI18nDelegate);

  @override
  Widget build(BuildContext context) {
    return StoreProvider(
      store: store,
      child: MaterialApp(
        title: 'Pocket Drive',
        debugShowCheckedModeBanner: true,
        theme: ThemeData(
          primaryColor: Colors.teal,
          accentColor: Colors.redAccent,
          iconTheme: IconThemeData(color: Colors.black38),
        ),
        routes: <String, WidgetBuilder>{
          '/login': (BuildContext context) => LoginPage(),
          '/station': (BuildContext context) => BottomNavigation(),
          // log out device, then jump to device list
          '/deviceList': (BuildContext context) {
            // cancel monitor of network connection
            store.state?.apis?.monitorCancel();
            // remove apis, device, reset config
            store.dispatch(UpdateApisAction(null));
            store.dispatch(DeviceLoginAction(null));
            return StationList(
              request: store.state.cloud,
              afterLogout: true,
            );
          },
        },
        home: (store?.state?.account?.id != null && store?.state?.apis != null)
            ? BottomNavigation()
            : (store?.state?.account?.id != null && store?.state?.cloud != null)
                ? StationList(
                    request: store.state.cloud,
                    afterLogout: true,
                  )
                : LoginPage(),
        localizationsDelegates: [
          flutterI18nDelegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate
        ],
      ),
    );
  }
}
