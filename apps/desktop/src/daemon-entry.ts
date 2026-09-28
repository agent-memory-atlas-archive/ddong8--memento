// Entry of the utility process that runs the local daemon.
import { main } from "@memento/daemon/cli";

// The desktop app asks for a clean stop over the parent port (signals don't
// reach a utility process the same way on every OS).
const port = (process as unknown as { parentPort?: { on(event: "message", cb: (e: { data: unknown }) => void): void } }).parentPort;
port?.on("message", (e) => {
  if ((e.data as { type?: string } | undefined)?.type === "stop") process.emit("SIGTERM");
});

main(["run"]).catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
