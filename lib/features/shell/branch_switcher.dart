import 'package:material_ui/material_ui.dart';

/// Holds every rail page alive; only the current one is painted and runs
/// animations. Switching shows the page that is already built and fades it
/// in quickly (no rebuild, no reload, scroll position kept).
class BranchSwitcher extends StatefulWidget {
  const BranchSwitcher({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<BranchSwitcher> createState() => _BranchSwitcherState();
}

class _BranchSwitcherState extends State<BranchSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: 1,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeOut,
  );

  @override
  void didUpdateWidget(BranchSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          // Same structure for every page, so switching never rebuilds one.
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: FadeTransition(
                opacity: i == widget.index
                    ? _opacity
                    : kAlwaysCompleteAnimation,
                child: RepaintBoundary(child: widget.children[i]),
              ),
            ),
          ),
      ],
    );
  }
}
