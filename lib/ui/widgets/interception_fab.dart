import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/interception/interception_bloc.dart';
import '../bloc/interception/interception_state.dart';
import '../../domain/entities/interception_mode.dart';

class InterceptionFAB extends StatelessWidget {
  const InterceptionFAB({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InterceptionBloc, InterceptionState>(
      builder: (context, state) {
        if (state is InterceptionDisabled || state is InterceptionInitial) {
          return const SizedBox.shrink();
        }

        final isPending = state is InterceptionPending;
        final mode = state is InterceptionEnabled
            ? state.mode
            : (state is InterceptionPending ? state.mode : InterceptionMode.none);

        return FloatingActionButton(
          onPressed: isPending ? () {} : null,
          backgroundColor: isPending ? Colors.orange : _getModeColor(mode),
          child: isPending
              ? _buildPulsingIcon()
              : Icon(_getModeIcon(mode)),
        );
      },
    );
  }

  Color _getModeColor(InterceptionMode mode) {
    switch (mode) {
      case InterceptionMode.requestOnly:
        return Colors.blue;
      case InterceptionMode.responseOnly:
        return Colors.green;
      case InterceptionMode.both:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getModeIcon(InterceptionMode mode) {
    switch (mode) {
      case InterceptionMode.requestOnly:
        return Icons.arrow_upward;
      case InterceptionMode.responseOnly:
        return Icons.arrow_downward;
      case InterceptionMode.both:
        return Icons.swap_vert;
      default:
        return Icons.block;
    }
  }

  Widget _buildPulsingIcon() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      builder: (context, value, child) {
        return Opacity(
          opacity: 0.5 + (value * 0.5),
          child: const Icon(Icons.pause_circle_filled, size: 32),
        );
      },
      onEnd: () {
        // Restart animation
      },
    );
  }
}