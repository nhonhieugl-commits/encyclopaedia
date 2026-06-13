# CLAUDE.md — Bách Khoa Toàn Thư Ops AI Agent

## Project Overview

AI agent cho nội bộ đội Merchant Operations. Cung cấp khả năng tra cứu thông minh, hỏi đáp tự động và quiz kiểm tra kiến thức dựa trên knowledge base của team.

**Stack:** Python 3.11 · FastAPI · Anthropic Claude SDK · SQLite · Docker  
**Deploy target:** GreenNode AgentBase (HTTP runtime)

---

## Architecture

```
agent.py          ← Entry point: FastAPI app + agentic loop
├── /health       ← Health check endpoint (required by AgentBase)
├── /chat         ← Main AI chat endpoint (streaming)
├── /api/docs     ← CRUD knowledge base documents
├── /api/quiz     ← Quiz questions CRUD + attempt tracking
└── /api/auth     ← JWT login/logout

tools/
├── search_knowledge_base()   ← Full-text search SQLite FTS5
├── get_section_content()     ← Fetch documents by section
├── get_quiz_questions()      ← Random quiz questions
└── log_quiz_attempt()        ← Save user score
```

## Database Schema

```sql
-- Knowledge base documents
CREATE TABLE documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    section INTEGER NOT NULL,  -- 1-5 (see sections below)
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    file_type TEXT,            -- pdf, docx, xlsx, md
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Full-text search index
CREATE VIRTUAL TABLE documents_fts USING fts5(
    title, content, content=documents, content_rowid=id
);

-- Quiz questions
CREATE TABLE quiz_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    section INTEGER NOT NULL,
    question TEXT NOT NULL,
    option_a TEXT NOT NULL,
    option_b TEXT NOT NULL,
    option_c TEXT NOT NULL,
    option_d TEXT NOT NULL,
    correct_answer TEXT NOT NULL CHECK(correct_answer IN ('A','B','C','D')),
    explanation TEXT
);

-- Quiz attempts
CREATE TABLE quiz_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    section INTEGER,
    score INTEGER,
    total INTEGER,
    taken_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Users
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT DEFAULT 'user' CHECK(role IN ('admin', 'user')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## Content Sections (5 phần)

| ID | Tên | Mô tả |
|----|-----|-------|
| 1 | Từ Điển Thuật Ngữ Ops | TPV, Lead, CR%, Onboard, Churn... |
| 2 | Quy Trình Chuẩn | SOPs, Memo, chính sách nội bộ |
| 3 | Cẩm Nang Xử Lý Sự Cố | Soundbox, lỗi kết nối, cổng thanh toán |
| 4 | Danh Mục Thiết Bị & Phần Cứng | Hướng dẫn sử dụng & reset thiết bị |
| 5 | Kiểm Tra Kiến Thức | Quiz trắc nghiệm A/B/C/D |

## Environment Variables

| Biến | Required | Default | Mô tả |
|------|----------|---------|-------|
| `ANTHROPIC_API_KEY` | ✅ | — | Claude API key |
| `JWT_SECRET` | ✅ | — | ≥32 ký tự, random |
| `MODEL` | ❌ | `claude-opus-4-5` | Claude model |
| `MAX_TOKENS` | ❌ | `4096` | Max tokens per response |
| `PORT` | ❌ | `3000` | HTTP port |
| `DB_PATH` | ❌ | `/app/data/ops.db` | SQLite database path |
| `UPLOAD_DIR` | ❌ | `/app/data/uploads` | File upload directory |
| `MAX_FILE_SIZE_MB` | ❌ | `20` | Upload size limit |
| `JWT_EXPIRES_IN` | ❌ | `8h` | Token expiry |
| `NODE_ENV` | ❌ | `development` | Environment |

## Agentic Loop

Agent sử dụng tool-use loop chuẩn của Anthropic:

```python
while True:
    response = client.messages.create(tools=TOOLS, messages=messages)
    if response.stop_reason == "end_turn":
        break
    if response.stop_reason == "tool_use":
        tool_results = execute_tools(response.content)
        messages.append({"role": "assistant", "content": response.content})
        messages.append({"role": "user", "content": tool_results})
```

## API Endpoints

### Authentication
- `POST /api/auth/login` — `{username, password}` → `{token, role}`
- `POST /api/auth/logout` — Invalidate token

### Chat (requires Bearer token)
- `POST /chat` — `{message, session_id?}` → streaming response
- `GET /chat/history/{session_id}` — Lấy lịch sử hội thoại

### Documents (Admin: full CRUD, User: read-only)
- `GET /api/docs?section=&search=` — List/search documents
- `GET /api/docs/{id}` — Get document
- `POST /api/docs` — Upload document (multipart)
- `DELETE /api/docs/{id}` — Delete document

### Quiz
- `GET /api/quiz?section=&count=10` — Get random questions
- `POST /api/quiz/attempt` — `{answers, section}` → `{score, results}`
- `GET /api/quiz/history` — User's past attempts

### System
- `GET /health` — Health check → `{status, timestamp, version}`
- `GET /api/stats` — Usage stats (Admin only)

## Running Locally

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Copy and configure env
cp .env.example .env
# Edit .env: set ANTHROPIC_API_KEY and JWT_SECRET

# 3. Run
python agent.py

# API available at http://localhost:3000
# Interactive docs at http://localhost:3000/docs
```

## Key Design Decisions

1. **Single file agent.py**: Toàn bộ logic trong một file để dễ deploy trên AgentBase
2. **FTS5 search**: SQLite Full-Text Search cho tốc độ tìm kiếm nhanh mà không cần Elasticsearch
3. **Streaming responses**: FastAPI StreamingResponse để UX tốt hơn khi Claude suy nghĩ lâu
4. **Tool use**: Agent có 4 tools để truy xuất knowledge base, không hallucinate thông tin không có trong DB
5. **Persistent volume**: DB và uploads mount vào `/app/data` để survive container restart

## Common Issues

| Vấn đề | Nguyên nhân | Fix |
|--------|-------------|-----|
| `ANTHROPIC_API_KEY not set` | Thiếu env var | Set key trên AgentBase dashboard |
| `Database locked` | Multiple writes | Đã dùng WAL mode — bình thường nếu thoáng qua |
| Agent trả lời "không có thông tin" | Document chưa upload | Admin upload tài liệu vào đúng section |
| Slow response | Claude đang dùng nhiều tools | Bình thường — streaming cho thấy tiến trình |
