import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:provider/provider.dart';

/// Builds the peer tab action buttons for a host widget.
typedef PeerTabActionsBuilder = List<Widget> Function(BuildContext context);

/// Bridge that lets the main window's left pane (owned by `DesktopHomePage`)
/// render the action buttons implemented by `PeerTabPage`'s state, without
/// moving that state out of the peer tab page.
class PeerTabActionsController extends ChangeNotifier {
  PeerTabActionsController._();

  static final PeerTabActionsController instance = PeerTabActionsController._();

  PeerTabActionsBuilder? _builder;
  PeerTabActionsBuilder? get builder => _builder;

  void register(PeerTabActionsBuilder builder) {
    _builder = builder;
    _notifyLater();
  }

  void unregister() {
    _builder = null;
    _notifyLater();
  }

  // Registration happens while the widget tree builds, so defer the
  // notification to avoid marking listeners dirty during build.
  void _notifyLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }
}

/// Renders the actions registered through [PeerTabActionsController].
/// Renders nothing while no [PeerTabPage] is mounted (for example in
/// incoming-only mode).
class PeerTabActionsBar extends StatelessWidget {
  const PeerTabActionsBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Keep tab-dependent actions in sync with the shared peer tab model.
    Provider.of<PeerTabModel>(context);
    return AnimatedBuilder(
      animation: PeerTabActionsController.instance,
      builder: (context, _) {
        final builder = PeerTabActionsController.instance.builder;
        if (builder == null) return const SizedBox.shrink();
        final actions = builder(context);
        if (actions.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        );
      },
    );
  }
}
