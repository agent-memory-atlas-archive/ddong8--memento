import unittest
from unittest.mock import AsyncMock, MagicMock
from server.services.ws_manager import DeviceConnectionManager
from server.api.devices import get_playback_source


class TestP2pPlayback(unittest.IsolatedAsyncioTestCase):
    async def test_ws_manager_p2p_info_cache(self):
        mgr = DeviceConnectionManager()
        self.assertIsNone(mgr.get_p2p_info("dev_nas"))

        mgr.set_p2p_info("dev_nas", {
            "ipv6": "240e:390:800:1234:5678::1",
            "port": 8765,
            "token": "secret-p2p-token",
        })

        info = mgr.get_p2p_info("dev_nas")
        self.assertIsNotNone(info)
        self.assertEqual(info["ipv6"], "240e:390:800:1234:5678::1")
        self.assertEqual(info["port"], 8765)
        self.assertEqual(info["token"], "secret-p2p-token")

    async def test_get_playback_source_with_and_without_p2p(self):
        from server.services.ws_manager import ws_manager
        
        # 1. Without P2P info
        mock_user = MagicMock(role="admin", id=1)
        mock_db = AsyncMock()
        mock_scalars = MagicMock()
        mock_scalars.first.return_value = None
        mock_exec_result = MagicMock()
        mock_exec_result.scalars.return_value = mock_scalars
        mock_db.execute.return_value = mock_exec_result
        mock_req = MagicMock(base_url="https://mem.ihasy.com", query_params={})

        res_no_p2p = await get_playback_source(
            device_id="device_test_1",
            path="/Volumes/Data/recording.mp4",
            request=mock_req,
            db=mock_db,
            _user=mock_user,
        )

        self.assertFalse(res_no_p2p["has_p2p"])
        self.assertIsNone(res_no_p2p["p2p_url"])
        self.assertIn("/api/devices/device_test_1/files/stream/recording.mp4", res_no_p2p["relay_url"])
        self.assertEqual(res_no_p2p["mime_type"], "video/mp4")
        self.assertEqual(res_no_p2p["filename"], "recording.mp4")

        # 2. With P2P info set on ws_manager
        ws_manager.set_p2p_info("device_test_1", {
            "ipv6": "2409:8a00:1000:2000::99",
            "port": 9000,
            "token": "token-abc-123",
        })

        res_p2p = await get_playback_source(
            device_id="device_test_1",
            path="/Volumes/Data/recording.mp4",
            request=mock_req,
            db=mock_db,
            _user=mock_user,
        )

        self.assertTrue(res_p2p["has_p2p"])
        self.assertIsNotNone(res_p2p["p2p_url"])
        self.assertTrue(res_p2p["p2p_url"].startswith("http://[2409:8a00:1000:2000::99]:9000/p2p/stream?"))
        self.assertIn("token=token-abc-123", res_p2p["p2p_url"])
        self.assertIn("path=%2FVolumes%2FData%2Frecording.mp4", res_p2p["p2p_url"])
        self.assertIn("recording.mp4", res_p2p["relay_url"])
