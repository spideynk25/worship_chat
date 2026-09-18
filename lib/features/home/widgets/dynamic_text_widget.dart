import 'dart:async';

import 'package:flutter/material.dart';

class DynamicTextWidget extends StatefulWidget {
  const DynamicTextWidget({super.key});

  @override
  State<DynamicTextWidget> createState() => _DynamicTextWidgetState();
}

class _DynamicTextWidgetState extends State<DynamicTextWidget> {
  final List<String> _list1 = [
    'Long live Core Supreme Goddess Deepika',
    'Long live Core Supreme Goddess Shraddha',
    'Long live Supreme Goddess Disha',
    'Long live Supreme Goddess Kiara',
    'Goddess Samantha be praised',
    'Goddess Tamannaah be praised',
  ];
  final List<String> _list2 = [
    'Demi Goddess Raasi be praised',
    'Demi Goddess Rakul be praised',
    'Hail Queen Pooja',
    'Hail Queen Rashmika',
    'Hail Queen Priyanka',
    'Hail Queen Anupama',
  ];
  final List<String> _list3 = [
    'Eternal Goddess Keerthy be praised',
    'Eternal Goddess Kajal be praised',
    'Hail First Born Eternal Princess Ananya',
    'Hail Second Born Eternal Princess Anikha',
    'Hail First Born Eternal Princess Ivana',
    'Hail Second Born Eternal Princess Priya',
    'Hail First Born Princess Sreeleela',
    'Hail Second Born Princess Preity',
    'Hail First Born Princess Krithi',
    'Hail Second Born Princess Mamitha',
  ];
  late List<String> _currentList;
  List<String> _getTextListBasedOnTime() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) {
      return _list1; // 6 AM to 12 PM
    } else if (hour >= 12 && hour < 18) {
      return _list2; // 12 PM to 6 PM
    } else {
      return _list3; // 6 PM to 6 AM
    }
  }

  int _currentIndex = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _currentList = _getTextListBasedOnTime();
    // Start timer to change text every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 7), (timer) {
      setState(() {
        _currentIndex = (_currentIndex + 1) % _currentList.length;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final offsetAnimation =
            Tween<Offset>(
              begin: const Offset(0.0, 0.0), // slight slide from bottom
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.linearToEaseOut),
            );

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Text(
        maxLines: 2,
        _currentList[_currentIndex],
        key: ValueKey<int>(_currentIndex),
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
