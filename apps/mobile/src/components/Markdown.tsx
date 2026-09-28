import { View } from "react-native";
import { useMarkdown } from "react-native-marked";

import { mono, useTheme } from "../lib/theme";

/** Markdown in the app's colours; long answers render as plain views inside the caller's scroll view. */
export function Markdown({ children }: { children: string }) {
  const t = useTheme();
  const elements = useMarkdown(children, {
    colorScheme: t.scheme,
    theme: { colors: { text: t.fg1, link: t.accent, code: t.code, border: t.border } },
    styles: {
      text: { fontSize: 15, lineHeight: 23, color: t.fg1 },
      paragraph: { marginVertical: 4 },
      h1: { fontSize: 20, fontWeight: "700", color: t.fg1 },
      h2: { fontSize: 18, fontWeight: "700", color: t.fg1 },
      h3: { fontSize: 16, fontWeight: "600", color: t.fg1 },
      codespan: { fontFamily: mono, fontSize: 13, backgroundColor: t.code },
      codeText: { fontFamily: mono, fontSize: 12.5, color: t.fg2 },
      code: { backgroundColor: t.code, borderRadius: 8, padding: 10 },
      li: { fontSize: 15, lineHeight: 23, color: t.fg1 },
      blockquote: { borderLeftColor: t.borderStrong, borderLeftWidth: 3, paddingLeft: 10 },
    },
  });
  return <View>{elements}</View>;
}
