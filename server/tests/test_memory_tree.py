import unittest
import uuid
from unittest.mock import AsyncMock, MagicMock

from server.api.memory import get_core_memory_tree
from server.db.models import User, UserMemory


class TestMemoryTree(unittest.IsolatedAsyncioTestCase):
    async def test_get_core_memory_tree_nesting(self):
        user = User(id=uuid.uuid4(), email="dev@example.com")

        # Root folder: Desktop
        folder_id = uuid.uuid4()
        folder_node = UserMemory(
            id=folder_id,
            user_id=user.id,
            category="rule",
            key="desktop",
            content="桌面端工程规范分支",
            is_folder=True,
            tree_path="/rules/desktop",
            parent_id=None,
        )

        # Child 1: windows_update_policy under folder
        child_id = uuid.uuid4()
        child_node = UserMemory(
            id=child_id,
            user_id=user.id,
            category="rule",
            key="windows_update_policy",
            content="Windows 桌面端必须使用 .zip 在位热替换",
            is_folder=False,
            tree_path="/rules/desktop/windows_update_policy",
            parent_id=folder_id,
        )

        # Root item: architecture_overview (no parent)
        arch_id = uuid.uuid4()
        arch_node = UserMemory(
            id=arch_id,
            user_id=user.id,
            category="architecture",
            key="three_tier",
            content="三层分层记忆模型",
            is_folder=False,
            tree_path="/architecture/three_tier",
            parent_id=None,
        )

        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_scalars = MagicMock()
        mock_scalars.all.return_value = [folder_node, child_node, arch_node]
        mock_result.scalars.return_value = mock_scalars
        mock_db.execute.return_value = mock_result

        resp = await get_core_memory_tree(db=mock_db, _user=user)

        self.assertEqual(resp["total_count"], 3)
        roots = resp["tree"]
        # There should be 2 root items: folder_node and arch_node
        self.assertEqual(len(roots), 2)

        folder_in_roots = next(r for r in roots if r["id"] == str(folder_id))
        self.assertTrue(folder_in_roots["is_folder"])
        self.assertEqual(len(folder_in_roots["children"]), 1)
        self.assertEqual(folder_in_roots["children"][0]["id"], str(child_id))
        self.assertEqual(folder_in_roots["children"][0]["key"], "windows_update_policy")


if __name__ == "__main__":
    unittest.main()
