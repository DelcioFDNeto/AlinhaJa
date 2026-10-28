import 'package:web/web.dart' as web;

/// `config.json` ao lado do `index.html`.
///
/// Resolve contra o `<base href>` do documento, não contra a URL atual: com
/// o app aberto em `/rh/alertas`, um caminho relativo apontaria para
/// `/rh/config.json`.
Uri? configUrl() => Uri.parse(web.document.baseURI).resolve('config.json');
