import json
import unittest
import uuid
from datetime import date
from unittest.mock import AsyncMock, MagicMock, patch

from server.db.models import User, UserMemory
from server.services.dreaming_service import (
    export_core_memory_markdown,
    run_dreaming_pipeline,
    sanitize_transient_text,
)


class TestDreamingService(unittest.IsolatedAsyncioTestCase):
    def test_sanitize_transient_text(self):
        raw = (
            "Here is an image: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAMkll"
            "And some huge code: " + ("abcdef1234567890" * 300)
        )
        cleaned = sanitize_transient_text(raw)
        self.assertIn("[image_base64_omitted]", cleaned)
        self.assertLess(len(cleaned), len(raw))

    async def test_export_core_memory_markdown(self):
        user = User(id=uuid.uuid4(), email="test@example.com")
        mem1 = UserMemory(
            user_id=user.id,
            category="rule",
            key="windows_update_policy",
            content="Windows 桌面端自更新必须使用 .zip 格式在位热替换，严禁下发 setup.exe。",
            confidence=0.95,
            source="dreaming",
        )
        mem2 = UserMemory(
            user_id=user.id,
            category="architecture",
            key="three_tier_memory",
            content="记忆采用三层金字塔：L1 工作会话，L2 每日研报，L3 长期核心准则。",
            confidence=0.98,
            source="manual",
        )

        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_scalars = MagicMock()
        mock_scalars.all.return_value = [mem1, mem2]
        mock_result.scalars.return_value = mock_scalars
        mock_db.execute.return_value = mock_result

        md = await export_core_memory_markdown(mock_db, user)
        self.assertIn("# MEMORY.md", md)
        self.assertIn("windows_update_policy", md)
        self.assertIn("three_tier_memory", md)
        self.assertIn("开发铁律与工程规范", md)
        self.assertIn("核心架构决策与设计模式", md)

    async def test_run_dreaming_pipeline_with_llm_reflection(self):
        user = User(id=uuid.uuid4(), email="dev@example.com")

        mock_db = AsyncMock()
        mock_db.add = MagicMock()

        def make_mock_result(scalar_items=None, all_items=None, one_item=None):
            m = MagicMock()
            sc = MagicMock()
            sc.all.return_value = scalar_items or []
            m.scalars.return_value = sc
            m.all.return_value = all_items or []
            m.scalar_one_or_none.return_value = one_item
            return m

        mock_llm_json = {
            "light_sleep_notes": "清洗了会话与工具日志",
            "rem_reflections": "发现用户致力于构建高性能桌面端记忆伴侣，重点优化了更新提权与后台长连接。",
            "deep_consolidations": "正式固化两项开发规范与架构决策",
            "promoted_memories": [
                {
                    "category": "rule",
                    "key": "windows_update_policy",
                    "content": "Windows 更新必须使用 .zip 在位热替换",
                    "confidence": 0.95,
                }
            ],
            "discovered_relations": [
                {
                    "source": "Windows更新",
                    "target": "PowerShell",
                    "relation": "uses",
                }
            ],
        }

        with patch("server.services.dreaming_service.get_ai_providers", return_value=[{"provider": "test"}]), \
             patch("server.services.dreaming_service.call_plain_chat", AsyncMock(return_value=json.dumps(mock_llm_json))):

            mock_ds = MagicMock()
            mock_ds.summary_date = date.today()
            mock_ds.title = "今日工作小结"
            mock_ds.summary = "完成了 Windows 自动更新修复"

            mock_db.execute.side_effect = [
                make_mock_result(scalar_items=[mock_ds]), # daily_summaries
                make_mock_result(scalar_items=[]),        # ask_convs
                make_mock_result(all_items=[]),           # recent_msgs
                make_mock_result(scalar_items=[]),        # existing_mems
                make_mock_result(one_item=None),          # check existing for promoted memory
                make_mock_result(one_item=None),          # check source entity
                make_mock_result(one_item=None),          # check target entity
            ]

            journal = await run_dreaming_pipeline(mock_db, user, days_back=1)

            self.assertEqual(journal.user_id, user.id)
            self.assertEqual(journal.stage_metrics["promoted_count"], 1)
            self.assertIn("清洗了会话与工具日志", journal.light_sleep_notes)
            self.assertIn("Windows 更新必须使用 .zip 在位热替换", journal.report_markdown)
            self.assertTrue(mock_db.commit.called)


if __name__ == "__main__":
    unittest.main()
