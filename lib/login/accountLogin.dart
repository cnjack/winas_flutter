import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

import './forgetPassword.dart';

import '../redux/redux.dart';
import '../common/request.dart';
import '../common/loading.dart';
import '../transfer/manager.dart';
import '../common/stationApis.dart';
import '../common/showSnackBar.dart';

class Login extends StatefulWidget {
  Login({Key key}) : super(key: key);

  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  String _status = 'account';

  // Focus action
  FocusNode myFocusNode;

  var request = Request();

  @override
  void initState() {
    super.initState();

    myFocusNode = FocusNode();
  }

  @override
  void dispose() {
    // Clean up the focus node when the Form is disposed
    myFocusNode.dispose();

    super.dispose();
  }

  String _phoneNumber = '18817301665';

  String _password = '12345678';

  String _error;

  _currentTextField() {
    if (_status == 'account') {
      return TextField(
        key: Key('account'),
        onChanged: (text) {
          setState(() => _error = null);
          _phoneNumber = text;
        },
        // controller: TextEditingController(text: _phoneNumber),
        autofocus: true,
        decoration: InputDecoration(
            labelText: "手机号",
            prefixIcon: Icon(Icons.person, color: Colors.white),
            errorText: _error),
        style: TextStyle(fontSize: 24),
        maxLength: 11,
        keyboardType: TextInputType.number,
      );
    }
    return TextField(
      key: Key('password'),
      onChanged: (text) {
        setState(() => _error = null);
        _password = text;
      },
      // controller: TextEditingController(text: _password),
      focusNode: myFocusNode,
      decoration: InputDecoration(
          labelText: "密码",
          prefixIcon: Icon(Icons.lock, color: Colors.white),
          errorText: _error),
      style: TextStyle(fontSize: 24),
      obscureText: true,
    );
  }

  accoutLogin(context, store, args) async {
    // dismiss keyboard
    FocusScope.of(context).requestFocus(FocusNode());

    // show loading, need `Navigator.pop(context)` to dismiss
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
      context: context,
    );

    var res = await request.req('token', args);
    var token = res.data['token'];
    var userUUID = res.data['id'];
    assert(token != null);
    assert(userUUID != null);

    // update Account
    store.dispatch(LoginAction(Account.fromMap(res.data)));

    var stationsRes = await request.req('stations', null);

    var stationLists = stationsRes.data['ownStations'];
    final currentDevice = stationLists.firstWhere(
        (s) =>
            s['online'] == 1 &&
            s['sn'] == 'test_b44-a529-4dcf-aa30-240a151d8e03',
        orElse: () => null);
    assert(currentDevice != null);

    var deviceSN = currentDevice['sn'];
    var lanIp = currentDevice['LANIP'];
    var deviceName = currentDevice['name'];

    List results = await Future.wait([
      request.req('localBoot', {'deviceSN': deviceSN}),
      request.req('localUsers', {'deviceSN': deviceSN}),
      request.req('localToken', {'deviceSN': deviceSN}),
      request.req('localDrives', {'deviceSN': deviceSN})
    ]);

    var lanToken = results[2].data['token'];

    assert(lanToken != null);

    // update StatinData
    store.dispatch(
      DeviceLoginAction(
        Device(
          deviceSN: deviceSN,
          deviceName: deviceName,
          lanIp: lanIp,
          lanToken: lanToken,
        ),
      ),
    );
    assert(results[1].data is List);

    // get current user data
    var user = results[1].data.firstWhere(
          (s) => s['winasUserId'] == userUUID,
          orElse: () => null,
        );
    store.dispatch(
      UpdateUserAction(
        User.fromMap(user),
      ),
    );

    // get current drives data
    List<Drive> drives = List.from(
      results[3].data.map((drive) => Drive.fromMap(drive)),
    );

    store.dispatch(
      UpdateDrivesAction(drives),
    );

    // station apis
    bool isCloud = false;
    String cookie = 'blabla';
    Apis apis =
        Apis(token, lanIp, lanToken, userUUID, isCloud, deviceSN, cookie);

    store.dispatch(
      UpdateApisAction(apis),
    );

    if (user['uuid'] != null) {
      // init TransferManager, load TransferItem
      TransferManager.init(user['uuid']).catchError(print);
    }
    return results;
  }

  void _nextStep(BuildContext context, store) {
    if (_status == 'account') {
      if (_phoneNumber.length != 11 || !_phoneNumber.startsWith('1')) {
        setState(() {
          _error = '请输入11位手机号';
        });
        return; // TODO: check phone number
      }
      setState(() {
        _status = 'password';
      });
      var future = Future.delayed(const Duration(milliseconds: 100),
          () => FocusScope.of(context).requestFocus(myFocusNode));
      future.then((res) => print('100ms later'));
    } else {
      // login
      if (_password.length == 0) {
        return;
      }
      final args = {
        'clientId': 'flutter_Test',
        'username': _phoneNumber,
        'password': _password
      };
      // login to account and device
      accoutLogin(context, store, args).then((res) {
        //remove all router, and push '/station'
        Navigator.pushNamedAndRemoveUntil(
            context, '/station', (Route<dynamic> route) => false);
      }).catchError((err) {
        // pop loading
        Navigator.pop(context);
        showSnackBar(context, '登录失败');
        print(err);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0.0, // no shadow
        actions: <Widget>[
          FlatButton(
              child: Text("忘记密码"),
              textColor: Colors.white,
              onPressed: () {
                // Navigator to Login
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) {
                    return ForgetPassword();
                  }),
                );
              }),
        ],
      ),
      floatingActionButton: Builder(
        builder: (ctx) {
          return StoreConnector<AppState, VoidCallback>(
            converter: (store) => () => _nextStep(ctx, store),
            builder: (context, callback) => FloatingActionButton(
                  onPressed: callback,
                  tooltip: '下一步',
                  backgroundColor: Colors.white70,
                  elevation: 0.0,
                  child: Icon(
                    Icons.chevron_right,
                    color: Colors.teal,
                    size: 48,
                  ),
                ),
          );
        },
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          primaryColor: Colors.white,
          accentColor: Colors.white,
          hintColor: Colors.white,
          brightness: Brightness.dark,
        ),
        child: Center(
          child: Container(
            constraints: BoxConstraints.expand(),
            padding: EdgeInsets.all(16),
            color: Colors.teal,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  child: Text(
                    '登录',
                    textAlign: TextAlign.left,
                    style: TextStyle(fontSize: 28.0, color: Colors.white),
                  ),
                  width: double.infinity,
                ),
                Container(height: 48.0),
                _currentTextField(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}