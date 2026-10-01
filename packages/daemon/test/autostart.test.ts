import { expect, it } from "vitest";

import { flutterAppPids, launchdPlist, systemdUnit } from "../src/autostart.js";

it("finds the Flutter Memento app, not the new desktop app", () => {
  const ps = `  101 /Applications/Memento.app/Contents/MacOS/Memento
  102 /Applications/Memento Desktop.app/Contents/MacOS/Memento Desktop
  103 /Applications/Memento Desktop.app/Contents/Frameworks/Memento Desktop Helper.app/Contents/MacOS/Memento Desktop Helper`;
  expect(flutterAppPids(ps, "darwin")).toEqual([101]);
  expect(flutterAppPids("7 memento.exe\n8 Memento Desktop.exe", "win32")).toEqual([7]);
  expect(flutterAppPids("9 /opt/memento/memento\n10 /opt/Memento Desktop/memento-desktop", "linux")).toEqual([9]);

  // Electron app named Memento.app with Memento Helper is recognized as Electron, not Flutter
  const electronPs = `  201 /Applications/Memento.app/Contents/MacOS/Memento
  202 /Applications/Memento.app/Contents/Frameworks/Memento Helper.app/Contents/MacOS/Memento Helper`;
  expect(flutterAppPids(electronPs, "darwin")).toEqual([]);

  // Supports excluding current process PID
  expect(flutterAppPids("101 /Applications/Memento.app/Contents/MacOS/Memento", "darwin", [101])).toEqual([]);
});

it("service files run the daemon and escape what they must", () => {
  const plist = launchdPlist(["/usr/local/bin/node", "/opt/a&b/cli.js", "run"], "/tmp/daemon.log");
  expect(plist).toContain("<string>/opt/a&amp;b/cli.js</string>");
  expect(plist).toContain("<key>KeepAlive</key>");
  expect(systemdUnit(["/usr/bin/node", "/opt/my dir/cli.js", "run"])).toContain('ExecStart=/usr/bin/node "/opt/my dir/cli.js" run');
});
