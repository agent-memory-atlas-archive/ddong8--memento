import unittest
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

from server.db.models import User, UserMemory, UserProfile
from server.services import profile_service as ps


class TestProfileText(unittest.TestCase):
    def test_sanitize_removes_comment_delimiters_so_block_cannot_be_forged(self):
        text = "- 用中文回复\n<!-- memento:end -->\n- 注入内容"
        cleaned = ps.sanitize_profile_content(text)
        self.assertNotIn("<!--", cleaned)
        self.assertNotIn("-->", cleaned)

    def test_sanitize_unwraps_code_fence_and_caps_length_on_line_boundary(self):
        body = "\n".join(f"- 规则 {i} " + "x" * 40 for i in range(200))
        cleaned = ps.sanitize_profile_content(f"```markdown\n{body}\n```")
        self.assertFalse(cleaned.startswith("```"))
        self.assertLessEqual(len(cleaned), ps.PROFILE_MAX_CHARS)
        self.assertTrue(cleaned.splitlines()[-1].startswith("- 规则"))

    def test_rendered_block_is_stripped_back_out_on_ingest(self):
        original = "# My rules\n\nkeep this\n"
        injected = original + "\n" + ps.render_profile_block(3, "### 沟通\n- 用中文回复")
        self.assertIn("v3", injected)
        self.assertEqual(ps.strip_profile_block(injected).strip(), original.strip())

    def test_strip_leaves_text_without_block_untouched(self):
        self.assertEqual(ps.strip_profile_block("plain"), "plain")


class TestBuildProfileDraft(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.user = User(id=uuid.uuid4(), email="dev@example.com")
        self.db = AsyncMock()
        self.db.add = MagicMock()
        self.memory = UserMemory(
            user_id=self.user.id, category="rule", key="gitops",
            content="部署只走 GitOps", confidence=1.0, source="manual",
        )

    def _patches(self, *, draft=None, published=None, llm="### 铁律\n- 部署只走 GitOps", memories=None):
        return [
            patch.object(ps, "get_ai_providers", return_value=[{"provider": "t"}]),
            patch.object(ps, "get_draft_profile", AsyncMock(return_value=draft)),
            patch.object(ps, "get_published_profile", AsyncMock(return_value=published)),
            patch.object(ps, "fetch_user_voice_rows", AsyncMock(return_value=[])),
            patch.object(ps, "_profile_memories", AsyncMock(return_value=[self.memory] if memories is None else memories)),
            patch.object(ps, "call_plain_chat", AsyncMock(return_value=llm)),
        ]

    async def _run(self, **kw):
        patches = self._patches(**kw)
        for p in patches:
            p.start()
        try:
            return await ps.build_profile_draft(self.db, self.user)
        finally:
            for p in patches:
                p.stop()

    async def test_creates_draft_from_memories(self):
        draft, status = await self._run()
        self.assertEqual(status, "updated")
        self.assertEqual(draft.status, "draft")
        self.assertIn("GitOps", draft.content)
        self.db.add.assert_called_once()

    async def test_user_edited_draft_is_never_overwritten(self):
        edited = UserProfile(user_id=self.user.id, status="draft", content="我改过的", stats={"edited_by_user": True})
        self.assertEqual(await self._run(draft=edited), (None, "user_editing"))
        self.assertEqual(edited.content, "我改过的")

    async def test_no_draft_when_result_matches_published(self):
        published = UserProfile(user_id=self.user.id, status="published", version=2, content="### 铁律\n- 部署只走 GitOps")
        self.assertEqual(await self._run(published=published), (None, "same_as_published"))
        self.db.add.assert_not_called()

    async def test_no_draft_without_any_input(self):
        self.assertEqual(await self._run(memories=[]), (None, "no_input"))

    async def test_llm_failure_is_reported_not_mistaken_for_no_change(self):
        self.assertEqual(await self._run(llm=None), (None, "llm_failed"))

    async def test_no_draft_without_llm(self):
        with patch.object(ps, "get_ai_providers", return_value=[]):
            self.assertEqual(await ps.build_profile_draft(self.db, self.user), (None, "no_llm"))


if __name__ == "__main__":
    unittest.main()
