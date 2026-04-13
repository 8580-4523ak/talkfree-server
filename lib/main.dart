import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_scaffold_messenger.dart';
import 'config/twilio_env.dart';
import 'theme/app_theme.dart';
import 'screens/app_root.dart';
import 'screens/number_selection_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/virtual_number_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseMessaging.instance.requestPermission();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e, st) {
    debugPrint('Could not load .env (copy .env.example → .env): $e\n$st');
  }
  if (kDebugMode) {
    debugPrint(
      'Twilio .env keys present: '
      '${TwilioEnv.accountSid != null && TwilioEnv.accountSid!.isNotEmpty}',
    );
  }
  runApp(const TalkFreeApp());
  // After first frame so AdMob never installs a native overlay before Flutter UI.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await MobileAds.instance.initialize();
    } catch (e, st) {
      debugPrint('MobileAds.initialize failed: $e\n$st');
    }
  });
}

class TalkFreeApp extends StatelessWidget {
  const TalkFreeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: appScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'TalkFree',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const TalkFreeRoot(),
      onGenerateRoute: (RouteSettings settings) {
        if (settings.name == NumberSelectionScreen.routeName) {
          return NumberSelectionScreen.createRoute(settings);
        }
        if (settings.name == VirtualNumberScreen.routeName) {
          return VirtualNumberScreen.createRoute(settings);
        }
        if (settings.name == SubscriptionScreen.routeName) {
          return SubscriptionScreen.createRoute();
        }
        return null;
      },
    );
  }
}
