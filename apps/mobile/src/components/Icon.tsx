import type { ColorValue } from "react-native";
import Svg, { Circle, Path, Rect } from "react-native-svg";

/** The web app's line icons (24-unit grid, stroked). */
const ICONS = {
  sparkles: [["p", "M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5z"], ["p", "M19 14l.7 2.3L22 17l-2.3.7L19 20l-.7-2.3L16 17l2.3-.7z"]],
  brain: [
    ["p", "M9 4.5a2.5 2.5 0 0 0-5 0v.5a2.5 2.5 0 0 0-2 4.5 2.5 2.5 0 0 0 .5 5A2.5 2.5 0 0 0 4 19a2.5 2.5 0 0 0 5 .5V4.5z"],
    ["p", "M15 4.5a2.5 2.5 0 0 1 5 0v.5a2.5 2.5 0 0 1 2 4.5 2.5 2.5 0 0 1-.5 5A2.5 2.5 0 0 1 20 19a2.5 2.5 0 0 1-5 .5V4.5z"],
  ],
  devices: [["r", 2, 4, 14, 10, 1.5], ["r", 14, 9, 8, 11, 1.5], ["p", "M5 18h6"]],
  calendar: [["r", 3, 5, 18, 16, 2], ["p", "M3 10h18M8 3v4M16 3v4"]],
  user: [["c", 12, 8, 4], ["p", "M4 21a8 8 0 0 1 16 0"]],
  search: [["c", 11, 11, 7], ["p", "M21 21l-4.3-4.3"]],
  chevron_right: [["p", "M9 5l7 7-7 7"]],
  chevron_left: [["p", "M15 5l-7 7 7 7"]],
  plus: [["p", "M12 5v14M5 12h14"]],
  layers: [["p", "M12 2l10 5-10 5L2 7z"], ["p", "M2 12l10 5 10-5M2 17l10 5 10-5"]],
  message: [["p", "M21 12a8 8 0 0 1-11.5 7.2L3 21l1.8-6.5A8 8 0 1 1 21 12z"]],
  clock: [["c", 12, 12, 9], ["p", "M12 7v5l3 2"]],
  book: [["p", "M4 3h12a4 4 0 0 1 4 4v14H8a4 4 0 0 1-4-4z"], ["p", "M4 17a4 4 0 0 1 4-4h12"]],
  terminal: [["p", "M4 17l6-5-6-5M12 19h8"]],
  edit: [["p", "M12 20h9"], ["p", "M16.5 3.5a2.1 2.1 0 1 1 3 3L7 19l-4 1 1-4z"]],
  activity: [["p", "M22 12h-4l-3 9L9 3l-3 9H2"]],
  zap: [["p", "M13 2L4 14h7l-1 8 9-12h-7z"]],
  arrow_up: [["p", "M12 19V5M5 12l7-7 7 7"]],
  refresh: [["p", "M3 12a9 9 0 0 1 15-6.7L21 8"], ["p", "M21 3v5h-5"], ["p", "M21 12a9 9 0 0 1-15 6.7L3 16"], ["p", "M3 21v-5h5"]],
  check: [["p", "M5 12l5 5L20 7"]],
  close: [["p", "M6 6l12 12M18 6l-12 12"]],
  trash: [["p", "M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"], ["p", "M6 6l1 14a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-14"]],
  link: [["p", "M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 1 0-7.07-7.07L11 5"], ["p", "M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 1 0 7.07 7.07L13 19"]],
  copy: [["r", 9, 9, 13, 13, 2], ["p", "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"]],
  cube: [["p", "M12 2L3 7v10l9 5 9-5V7z"], ["p", "M3 7l9 5 9-5M12 12v10"]],
  stop: [["r", 6, 6, 12, 12, 2]],
  moon: [["p", "M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"]],
} as const;

export type IconName = keyof typeof ICONS;

export function Icon({ name, size = 18, color, strokeWidth = 1.8 }: { name: IconName; size?: number; color: ColorValue; strokeWidth?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      {ICONS[name].map((shape, i) => {
        if (shape[0] === "p") return <Path key={i} d={shape[1]} />;
        if (shape[0] === "c") return <Circle key={i} cx={shape[1]} cy={shape[2]} r={shape[3]} />;
        return <Rect key={i} x={shape[1]} y={shape[2]} width={shape[3]} height={shape[4]} rx={shape[5]} />;
      })}
    </Svg>
  );
}
