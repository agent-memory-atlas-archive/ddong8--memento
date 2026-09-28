import { expect, it } from "vitest";

import { flutterAppPids, launchdPlist, systemdUnit } from "../src/autostart.js";

it("finds the Flutter Memento app, not the new desktop app", () => {
  const ps = `  101 /Applications/Memento.app/Contents/MacOS/Memento
  102 /Applications/Memento Desktop.app/Contents/MacOS/Memento Desktop
  103 /Applications/Memento Desktop.app/Contents/Frameworks/Memento Desktop Helper.app/Contents/MacOS/Memento Desktop Helper`;
  expect(flutterAppPids(ps, "darwin")).toEqual([101]);
  expect(flutterAppPids("7 memento.exe\n8 Memento Desktop.exe", "win32")).toEqual([7]);
  expect(flutterAppPids("9 /opt/memento/memento\n10 /opt/Memento Desktop/memento-desktop", "linux")).toEqual([9]);
});

it("service files run the daemon and escape what they must", () => {
  const plist = launchdPlist(["/usr/local/bin/node", "/opt/a&b/cli.js", "run"], "/tmp/daemon.log");
  expect(plist).toContain("<string>/opt/a&amp;b/cli.js</string>");
  expect(plist).toContain("<key>KeepAlive</key>");
  expect(systemdUnit(["/usr/bin/node", "/opt/my dir/cli.js", "run"])).toContain('ExecStart=/usr/bin/node "/opt/my dir/cli.js" run');
});
