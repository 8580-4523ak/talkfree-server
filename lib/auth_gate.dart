import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'theme/talkfree_colors.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: TalkFreeColors.backgroundTop,
            body: Center(
              child: CircularProgressIndicator(
                color: TalkFreeColors.beigeGold,
              ),
            ),
          );
        }
        final User? user = snapshot.data;
        if (user != null) {
          return DashboardScreen(user: user);
        }
        return const LoginScreen();
      },
    );
  }
}
