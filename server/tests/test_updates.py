"""Tests for server.api.updates without pytest dependency."""

import asyncio
import tempfile
import unittest
from pathlib import Path

from fastapi import FastAPI
from httpx import AsyncClient, ASGITransport

import server.api.updates as updates_mod
from server.api.updates import router, _compare_semver


class TestUpdatesApi(unittest.TestCase):
    def test_semver_comparison(self):
        self.assertTrue(_compare_semver("1.0.1", "1.0.0"))
        self.assertTrue(_compare_semver("2.0.0", "1.9.9"))
        self.assertFalse(_compare_semver("1.0.0", "1.0.0"))
        self.assertFalse(_compare_semver("0.9.0", "1.0.0"))

    def test_update_check_no_updates(self):
        async def run():
            with tempfile.TemporaryDirectory() as tmpdir:
                updates_mod._UPDATES_DIR = Path(tmpdir)
                app = FastAPI()
                app.include_router(router)

                transport = ASGITransport(app=app)
                async with AsyncClient(transport=transport, base_url="http://test") as client:
                    res = await client.get("/api/system/update/check?platform=windows&version=1.0.0")
                    self.assertEqual(res.status_code, 200)
                    data = res.json()
                    self.assertFalse(data["has_update"])

        asyncio.run(run())

    def test_update_check_and_download_with_asset(self):
        async def run():
            with tempfile.TemporaryDirectory() as tmpdir:
                updates_dir = Path(tmpdir)
                updates_mod._UPDATES_DIR = updates_dir

                # Create dummy update zip
                zip_file = updates_dir / "memento-windows-v1.0.2.zip"
                zip_file.write_bytes(b"dummy zip binary content")

                app = FastAPI()
                app.include_router(router)

                transport = ASGITransport(app=app)
                async with AsyncClient(transport=transport, base_url="http://test") as client:
                    res = await client.get("/api/system/update/check?platform=windows&version=1.0.0")
                    self.assertEqual(res.status_code, 200)
                    data = res.json()
                    self.assertTrue(data["has_update"])
                    self.assertEqual(data["latest_version"], "1.0.2")
                    self.assertEqual(data["asset_name"], "memento-windows-v1.0.2.zip")
                    self.assertIsNotNone(data["download_url"])

                    # Test downloading the asset
                    res_dl = await client.get(data["download_url"])
                    self.assertEqual(res_dl.status_code, 200)
                    self.assertEqual(res_dl.content, b"dummy zip binary content")

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
