import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenWelcome', true);
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBackgroundGradient(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    children: [
                      _buildPage1(),
                      _buildPage2(),
                      _buildPage3(),
                    ],
                  ),
                ),
                _buildPageIndicator(),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _buildColorForIndex(),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _currentPage == 2 ? 'Get Started' : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _buildColorForIndex() {
    return _currentPage == 0
                          ? Colors.blue
                          : _currentPage == 1
                          ? Colors.amber.shade600
                          : Colors.green;
  }

  Widget _buildBackgroundGradient() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _currentPage == 0
              ? [
            Colors.blue.shade50,
            Colors.blue.shade100,
            Colors.white,
          ]
              : _currentPage == 1
              ? [
            Colors.amber.shade50,
            Colors.orange.shade50,
            Colors.white,
          ]
              : [
            Colors.green.shade50,
            Colors.teal.shade50,
            Colors.white,
          ],
        ),
      ),
      child: CustomPaint(
        painter: _CurvedBackgroundPainter(page: _currentPage),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildPage1() {
    return const Padding(
      padding: EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dns_rounded,
            size: 100,
            color: Colors.blue,
          ),
          SizedBox(height: 40),
          Text(
            'Arbiter is mock server and/or a middleware',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          Text(
            'With Arbiter, you can mock the response and/or use it as a middleware.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPage2() {
    return const Padding(
      padding: EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 100,
            color: Colors.amber,
          ),
          SizedBox(height: 40),
          Text(
            'Why I built Arbiter?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          Text(
            'Short answer, to make my development time faster. In cases when there is a change in a single API, we need to mock the response in the codebase and then wait until the backend is deployed. With Arbiter we just select which endpoint to mock and tada 🎉!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPage3() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.rocket_launch,
            size: 100,
            color: Colors.green,
          ),
          const SizedBox(height: 40),
          const Text(
            'How to use it?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'It\'s easy as pie 🥧',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _AnimatedSteps(isVisible: _currentPage == 2),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
            (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentPage == index ? _buildColorForIndex() : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSteps extends StatefulWidget {
  final bool isVisible;

  const _AnimatedSteps({required this.isVisible});

  @override
  State<_AnimatedSteps> createState() => _AnimatedStepsState();
}

class _CurvedBackgroundPainter extends CustomPainter {
  final int page;

  _CurvedBackgroundPainter({required this.page});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = page == 0
          ? Colors.blue.withOpacity(0.1)
          : page == 1
          ? Colors.amber.withOpacity(0.1)
          : Colors.green.withOpacity(0.1);

    final path = Path();

    // Top curved wave
    path.moveTo(0, 0);
    path.lineTo(0, size.height * 0.2);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.15,
      size.width * 0.5,
      size.height * 0.2,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.25,
      size.width,
      size.height * 0.2,
    );
    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);

    // Bottom curved wave
    final bottomPath = Path();
    bottomPath.moveTo(0, size.height);
    bottomPath.lineTo(0, size.height * 0.8);
    bottomPath.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.85,
      size.width * 0.5,
      size.height * 0.8,
    );
    bottomPath.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.75,
      size.width,
      size.height * 0.8,
    );
    bottomPath.lineTo(size.width, size.height);
    bottomPath.close();

    canvas.drawPath(bottomPath, paint);

    // Add some decorative circles
    final circlePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = paint.color.withOpacity(0.3);

    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.1),
      30,
      circlePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.9),
      40,
      circlePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.85),
      25,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(_CurvedBackgroundPainter oldDelegate) {
    return oldDelegate.page != page;
  }
}

class _AnimatedStepsState extends State<_AnimatedSteps>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  final List<String> _steps = [
    'Set the base url of your app to localhost',
    'To use mock, create mock',
    'To use middleware, put the baseUrl in the App',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _animations = List.generate(
      3,
          (index) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            index * 0.2,
            0.6 + (index * 0.2),
            curve: Curves.elasticOut,
          ),
        ),
      ),
    );

    if (widget.isVisible) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_AnimatedSteps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        _steps.length,
            (index) => AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            final animValue = _animations[index].value.clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, (1 - animValue) * 20),
              child: Opacity(
                opacity: animValue,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4, right: 12),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _steps[index],
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}