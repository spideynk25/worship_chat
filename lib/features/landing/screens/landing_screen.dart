import 'package:flutter/material.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/widgets/custom_button.dart';
import 'package:worship_chat/features/auth/screens/login_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              height: 50,
            ),
            const Text(
              'Welcome Slaves',
              style: TextStyle(fontSize: 33, fontWeight: FontWeight.w600),
            ),
            SizedBox(
              height: size.height / 9,
            ),
            Image.asset(
              'assets/auth_images/supreme_goddess_deepika.png',
              height: 340,
              width: 340,
              // color: tabColor,
            ),
            SizedBox(
              height: size.height / 9,
            ),
            const Padding(
              padding: EdgeInsets.all(15.0),
              child: Text(
                'Get Ready to Serve us our Slaves. You Guys are ours after you entered in this app',
                style: TextStyle(color: greyColor),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            SizedBox(
                width: size.width * 0.75,
                child: CustomButton(
                    text: 'AGREE TO BE A SLAVE',
                    onPressed: () {
                      Navigator.pushNamed(context,LoginScreen.routeName
                      );
                    }))
          ],
        ),
      ),
    );
  }
}
