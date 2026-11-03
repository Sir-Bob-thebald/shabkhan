import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/artwork.dart';
import '../services/art_saver.dart';
import '../services/library.dart';
import '../services/net.dart';

/// Builds [child] only once [url] has loaded, so nothing (no empty frame, no
/// caption) shows while offline or when the image is gone.
/// How artwork images are loaded; tests swap in local images.
ImageProvider Function(String url) artImage =
    (url) => NetworkImage(url, headers: const {'User-Agent': Net.userAgent});

class _WhenLoaded extends StatefulWidget {
  final String url;
  final Widget Function(BuildContext context, ImageProvider image) builder;
  const _WhenLoaded({required this.url, required this.builder});

  @override
  State<_WhenLoaded> createState() => _WhenLoadedState();
}

class _WhenLoadedState extends State<_WhenLoaded> {
  late ImageProvider _image;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (_, _) => mounted ? setState(() => _ok = true) : null,
    onError: (_, _) {},
  );
  bool _ok = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_WhenLoaded old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    _stream?.removeListener(_listener);
    _ok = false;
    _image = artImage(widget.url);
    _stream = _image.resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ok ? widget.builder(context, _image) : const SizedBox.shrink();
}

/// The artwork as a faint picture behind a Tonight card, fading in from the
/// card's trailing edge.
class ArtBackdrop extends StatelessWidget {
  final Artwork art;
  const ArtBackdrop(this.art, {super.key});

  @override
  Widget build(BuildContext context) {
    return _WhenLoaded(
      url: art.imageUrl,
      builder: (context, image) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [Colors.transparent, Colors.black],
          stops: [0.15, 0.85],
        ).createShader(rect, textDirection: Directionality.of(context)),
        child: Opacity(
          opacity: 0.28,
          child: Image(image: image, fit: BoxFit.cover, alignment: Alignment.center),
        ),
      ),
    );
  }
}

/// The artwork at the top of the reader: a soft picture that fades into the
/// page, with its title, artist, date and origin, a like button and, once
/// liked, a download button.
class ArtHeader extends StatefulWidget {
  final Library library;
  final Artwork art;
  const ArtHeader({super.key, required this.library, required this.art});

  @override
  State<ArtHeader> createState() => _ArtHeaderState();
}

class _ArtHeaderState extends State<ArtHeader> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final where = await ArtSaver.save(widget.art);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(where)));
    } on Exception catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.art;
    final liked = widget.library.isArtLiked(a);
    final details = [a.date, a.origin].whereType<String>().join(' · ');
    return _WhenLoaded(
      url: a.imageUrl,
      builder: (context, image) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.55, 1],
              ).createShader(rect),
              child: Opacity(
                opacity: 0.75,
                child: Image(image: image, height: 260, fit: BoxFit.cover, alignment: const Alignment(0, -0.3)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: a.pageUrl == null
                        ? null
                        : () => launchUrl(Uri.parse(a.pageUrl!), mode: LaunchMode.externalApplication),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
                        Text(
                          [if (details.isNotEmpty) details, a.credit].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: liked ? 'Unlike' : 'Like this picture',
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                  color: liked ? theme.colorScheme.primary : null,
                  onPressed: () => widget.library.toggleArtLike(a),
                ),
                if (liked)
                  IconButton(
                    tooltip: 'Download the picture',
                    icon: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download),
                    onPressed: _saving ? null : _save,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
