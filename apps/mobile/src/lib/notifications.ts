import Constants from "expo-constants";
import * as Device from "expo-device";
import * as Notifications from "expo-notifications";
import { Platform } from "react-native";

// Configure how notifications appear when the app is in the foreground
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

/**
 * Trigger an immediate native system notification with sound, banner and haptics on device.
 */
export async function triggerLocalNotification(
  title: string,
  body: string,
  data?: Record<string, unknown>,
): Promise<void> {
  if (Platform.OS === "web") return;
  try {
    await Notifications.scheduleNotificationAsync({
      content: {
        title,
        body,
        sound: true,
        badge: 1,
        data: data || {},
      },
      trigger: null,
    });
  } catch (err) {
    console.warn("Failed to trigger local notification:", err);
  }
}

/**
 * Request notification permissions and fetch the Expo Push Token for this device.
 */
export async function registerForPushNotificationsAsync(): Promise<string | null> {
  if (Platform.OS === "web") return null;

  if (Platform.OS === "android") {
    await Notifications.setNotificationChannelAsync("default", {
      name: "Memento 通知",
      importance: Notifications.AndroidImportance.MAX,
      vibrationPattern: [0, 250, 250, 250],
      lightColor: "#7C3AED",
    });
  }

  const { status: existingStatus } = await Notifications.getPermissionsAsync();
  let finalStatus = existingStatus;
  if (existingStatus !== "granted") {
    const { status } = await Notifications.requestPermissionsAsync();
    finalStatus = status;
  }
  if (finalStatus !== "granted") {
    return null;
  }

  try {
    const projectId =
      Constants?.expoConfig?.extra?.eas?.projectId ??
      Constants?.easConfig?.projectId;
    const tokenData = await Notifications.getExpoPushTokenAsync(
      projectId ? { projectId } : undefined,
    );
    return tokenData.data;
  } catch (err) {
    console.warn("Failed to get Expo push token:", err);
    return null;
  }
}

/**
 * Register this device's push token with the Memento backend.
 */
export async function syncPushTokenToServer(
  server: string,
  authToken: string,
  deviceToken: string,
): Promise<boolean> {
  try {
    const base = server.replace(/\/+$/, "");
    const res = await fetch(`${base}/api/notify/device-token`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify({ token: deviceToken, platform: Platform.OS }),
    });
    return res.ok;
  } catch (err) {
    console.warn("Failed to sync push token to server:", err);
    return false;
  }
}

/**
 * Unregister this device's push token from the Memento backend upon sign-out.
 */
export async function unregisterPushTokenFromServer(
  server: string,
  authToken: string,
  deviceToken: string,
): Promise<void> {
  try {
    const base = server.replace(/\/+$/, "");
    await fetch(`${base}/api/notify/device-token`, {
      method: "DELETE",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify({ token: deviceToken, platform: Platform.OS }),
    });
  } catch (err) {
    console.warn("Failed to unregister push token:", err);
  }
}
