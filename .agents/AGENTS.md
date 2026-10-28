# Regras do Projeto AlinhaJá

- **Gerenciamento de Branches:** Este projeto é a ramificação oficial do AlinhaJa. Todas as alterações, commits e pushs devem ser feitos **EXCLUSIVAMENTE** na branch `AlinhaJa`. **JAMAIS** faça commits ou merges para as branches `dev` ou `main`.
- **Uso de Ícones (Material Icons):** Evite utilizar as variantes `_rounded` ou `_outlined` dos ícones (ex: `Icons.vpn_key_rounded`). Em builds para a web, devido a problemas de cache e tree-shaking da fonte MaterialIcons com codepoints altos (`0xf___`), esses ícones podem renderizar em branco. Utilize sempre as versões base (`Icons.vpn_key`, `Icons.check_circle`, etc) com codepoints estáveis (`0xe___`).
