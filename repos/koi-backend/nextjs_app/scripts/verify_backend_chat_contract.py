"""Read-only AST contract audit. No API runtime, Firebase, inference or network."""
import ast
import json
from pathlib import Path
# scripts -> nextjs_app -> koi-backend -> repos
backend = Path(__file__).resolve().parents[3] / "koi-ai-engine"
schemas = ast.parse((backend / "app/models/schemas.py").read_text(encoding="utf-8"))
routes = ast.parse((backend / "app/api/routes.py").read_text(encoding="utf-8"))
security = (backend / "app/core/security.py").read_text(encoding="utf-8")
classes = {node.name: node for node in schemas.body if isinstance(node, ast.ClassDef)}
def fields(name):
    return {node.target.id: ast.unparse(node.annotation) for node in classes[name].body if isinstance(node, ast.AnnAssign)}
assert fields("SessionTurn")["role"] == "Literal['user', 'assistant']"
assert set(fields("ChatRequest")) == {"message", "session_history"}
assert set(fields("ChatResponse")) == {"reply", "companion_state", "latency_ms"}
assert fields("CompanionState") == {"emotion": "str", "intensity": "float"}
intensity = next(node for node in classes["CompanionState"].body if isinstance(node, ast.AnnAssign) and node.target.id == "intensity")
assert {key.arg: ast.literal_eval(key.value) for key in intensity.value.keywords} == {"ge": 0.0, "le": 1.0}
chat = next(node for node in routes.body if isinstance(node, ast.AsyncFunctionDef) and node.name == "chat")
assert any(isinstance(node, ast.Call) and ast.unparse(node.func) == "Depends" and ast.unparse(node.args[0]) == "verify_firebase_token" for node in ast.walk(chat))
assert any(isinstance(node, ast.Call) and ast.unparse(node.func) == "router.post" and node.args[0].value == "/api/v1/chat" and any(key.arg == "response_model" and ast.unparse(key.value) == "ChatResponse" for key in node.keywords) for node in chat.decorator_list)
assert any(isinstance(node, ast.Return) and isinstance(node.value, ast.Call) and ast.unparse(node.value.func) == "inference_service.generate_reply" for node in ast.walk(chat))
assert not any(isinstance(node, (ast.Yield, ast.YieldFrom)) for node in ast.walk(chat))
assert "StreamingResponse" not in (backend / "app/api/routes.py").read_text(encoding="utf-8")
assert "firebase_auth.verify_id_token(token)" in security
print(json.dumps({"passed": True, "verification": "static AST/source only; not a running FastAPI or authenticated test", "transport": "JSON", "history_roles": ["user", "assistant"], "authentication": "Firebase verify_id_token dependency", "request_fields": fields("ChatRequest"), "response_fields": fields("ChatResponse")}, indent=2))

source = (backend / "app/services/inference_service.py").read_text(encoding="utf-8")
compile(source, "inference_service.py", "exec")
assert "last_raw[:500]" not in source, "Raw generation output must not leak in failure diagnostics"
