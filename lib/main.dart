import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:colorful_safe_area/colorful_safe_area.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

const String baseURL = 'giftamizer.com';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://giftamizer.com',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewogICJyb2xlIjogImFub24iLAogICJpc3MiOiAic3VwYWJhc2UiLAogICJpYXQiOiAxNjk1MDIwNDAwLAogICJleHAiOiAxODUyODczMjAwCn0.iMJi-OrGmLKRQfxxXma-OnOXEstXpo9cZhj9zmtpr2w',
    authCallbackUrlHostname: 'login-callback',
    authFlowType: AuthFlowType.pkce,
    debug: true,
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Giftamizer',
      theme: ThemeData().copyWith(
        primaryColor: Colors.white,
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.white,
      ),
      themeMode: ThemeMode.system, // device controls theme
      debugShowCheckedModeBanner: false,
      home: const WebViewApp(),
    );
  }
}

class WebViewApp extends StatefulWidget {
  const WebViewApp({super.key});

  @override
  WebViewAppState createState() => WebViewAppState();
}

class WebViewAppState extends State<WebViewApp> {
  final GlobalKey webViewKey = GlobalKey();

  InAppWebViewController? webViewController;
  InAppWebViewGroupOptions settings = InAppWebViewGroupOptions(
    crossPlatform: InAppWebViewOptions(
        javaScriptEnabled: true,
        supportZoom: false,
        useShouldOverrideUrlLoading: true,
        allowUniversalAccessFromFileURLs: true,
        allowFileAccessFromFileURLs: true),
    ios: IOSInAppWebViewOptions(),
    android: AndroidInAppWebViewOptions(
        domStorageEnabled: true,
        databaseEnabled: true,
        clearSessionCache: true,
        thirdPartyCookiesEnabled: true,
        allowFileAccess: true,
        allowContentAccess: true),
  );

  PullToRefreshController? pullToRefreshController;
  PullToRefreshOptions pullToRefreshSettings = PullToRefreshOptions(
    color: Colors.green,
  );

  @override
  void initState() {
    _setupAuthListener();
    super.initState();

    pullToRefreshController = kIsWeb
        ? null
        : PullToRefreshController(
            options: pullToRefreshSettings,
            onRefresh: () async {
              if (defaultTargetPlatform == TargetPlatform.android) {
                webViewController?.reload();
              } else if (defaultTargetPlatform == TargetPlatform.iOS) {
                webViewController?.loadUrl(
                    urlRequest:
                        URLRequest(url: await webViewController?.getUrl()));
              }
            },
          );
  }

  void _setupAuthListener() {
    supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        var url =
            'https://giftamizer.com/signin?accessToken=${data.session?.accessToken}&refreshToken=${data.session?.refreshToken}';

        webViewController?.loadUrl(urlRequest: URLRequest(url: Uri.parse(url)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          // detect Android back button click
          final controller = webViewController;
          if (controller != null) {
            if (await controller.canGoBack()) {
              controller.goBack();
              return false;
            }
          }
          return true;
        },
        child: Scaffold(
            body: ColorfulSafeArea(
                color: Colors.green,
                child: Column(children: <Widget>[
                  Expanded(
                      child: InAppWebView(
                    key: webViewKey,
                    initialUrlRequest:
                        URLRequest(url: Uri.parse('https://$baseURL')),
                    initialOptions: settings,
                    pullToRefreshController: pullToRefreshController,
                    onWebViewCreated: (InAppWebViewController controller) {
                      webViewController = controller;
                    },

                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                      var uri = navigationAction.request.url!;

                      // Google auth
                      if (uri.toString().contains(
                          '$baseURL/auth/v1/authorize?provider=google')) {
                        await supabase.auth.signInWithOAuth(Provider.google,
                            redirectTo:
                                'com.giftamizer.giftamizer://login-callback',
                            queryParams: {'response_type': 'code'});
                        return NavigationActionPolicy.CANCEL;
                      }

                      // Facebook auth
                      if (uri.toString().contains(
                          '$baseURL/auth/v1/authorize?provider=facebook')) {
                        await supabase.auth.signInWithOAuth(Provider.facebook,
                            redirectTo:
                                'com.giftamizer.giftamizer://login-callback',
                            queryParams: {'response_type': 'code'});
                        return NavigationActionPolicy.CANCEL;
                      }

                      if (!uri.toString().contains(baseURL)) {
                        if (!await launchUrl(uri)) {
                          throw Exception('Could not launch $uri');
                        }
                        // and cancel the request
                        return NavigationActionPolicy.CANCEL;
                      }

                      return NavigationActionPolicy.ALLOW;
                    },

                    onLoadStop: (controller, url) {
                      pullToRefreshController?.endRefreshing();
                    },
                    // onReceivedError: (controller, request, error) {
                    //   pullToRefreshController?.endRefreshing();
                    // },
                    onProgressChanged: (controller, progress) {
                      if (progress == 100) {
                        pullToRefreshController?.endRefreshing();
                      }
                    },
                  )),
                ]))));
  }
}
