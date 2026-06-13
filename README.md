# 📚 Bách Khoa Toàn Thư Ops — AI Agent

> Internal Knowledge Base AI cho đội Merchant Operations  
> Python 3.11 + FastAPI + Anthropic Claude + SQLite | Deploy: GreenNode AgentBase

---

## Tổng quan

AI Agent thay thế tra cứu thủ công — nhân viên Ops chat trực tiếp bằng tiếng Việt để:
- Tra thuật ngữ: "TPV là gì?", "CR% bao nhiêu là tốt?"
- Lấy SOP: "Quy trình onboard merchant mới?"
- Xử lý sự cố: "Soundbox không phát âm, làm gì?"
- Ôn luyện: "Cho tôi làm quiz 10 câu về thiết bị"

---

## Yêu cầu hệ thống

| Công cụ | Phiên bản |
|---------|-----------|
| Python | >= 3.11 |
| Docker | >= 24.x (để deploy) |
| Anthropic API Key | Bất kỳ plan nào |

---

## Chạy local (Development)

### 1. Clone và cài đặt

```bash
git clone <your-repo-url>
cd ops-agent

pip install -r requirements.txt
```

### 2. Cấu hình môi trường

```bash
cp .env.example .env
```

Sửa file `.env`:

```env
ANTHROPIC_API_KEY=sk-ant-...      # Bắt buộc
JWT_SECRET=random_string_min_32   # Bắt buộc — dùng: openssl rand -hex 32
PORT=3000
NODE_ENV=development
```

### 3. Chạy agent

```bash
python agent.py
```

Agent chạy tại **http://localhost:3000**  
Interactive API docs: **http://localhost:3000/docs**

### 4. Test nhanh

```bash
# Health check
curl http://localhost:3000/health

# Đăng nhập
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "Admin@123"}'
# → {"token": "eyJ...", "role": "admin"}

# Chat với AI
TOKEN="eyJ..."  # token từ bước trên
curl -X POST http://localhost:3000/chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "TPV là gì?"}' \
  --no-buffer
```

---

## Deploy lên GreenNode AgentBase

### Bước 1 — Build Docker image

```bash
docker build -t ops-agent:latest .

# Test local
docker run -d --name ops-test \
  -p 3000:3000 \
  -v $(pwd)/local-data:/app/data \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e JWT_SECRET=$(openssl rand -hex 32) \
  -e NODE_ENV=production \
  ops-agent:latest

curl http://localhost:3000/health
# → {"status":"ok","timestamp":"..."}
```

### Bước 2 — Push lên registry

```bash
# Docker Hub
docker tag ops-agent:latest your-username/ops-agent:latest
docker push your-username/ops-agent:latest

# Hoặc GreenNode Registry
docker tag ops-agent:latest registry.greennode.ai/your-org/ops-agent:latest
docker push registry.greennode.ai/your-org/ops-agent:latest
```

### Bước 3 — Deploy trên AgentBase

1. Vào **[greennode.ai](https://greennode.ai)** → **AgentBase** → **Deploy new agent**
2. Chọn **Runtime: HTTP**
3. Điền:
   - **Image:** `your-username/ops-agent:latest`
   - **Port:** `3000`
   - **Health check path:** `/health`
4. **Persistent Volume:** Mount `/app/data` — size 5GB
5. **Environment Variables** (bảng dưới)
6. Nhấn **Deploy** (~2–3 phút)
7. Copy URL public → chia sẻ cho team

---

## Biến môi trường

| Biến | Bắt buộc | Default | Mô tả |
|------|----------|---------|-------|
| `ANTHROPIC_API_KEY` | ✅ | — | Claude API key |
| `JWT_SECRET` | ✅ | — | Chuỗi random ≥32 ký tự |
| `MODEL` | ❌ | `claude-opus-4-5` | Claude model |
| `MAX_TOKENS` | ❌ | `4096` | Max tokens/response |
| `PORT` | ❌ | `3000` | HTTP port |
| `MAX_FILE_SIZE_MB` | ❌ | `20` | Upload size limit |
| `JWT_EXPIRES_IN` | ❌ | `8h` | Token expiry (`8h`, `30m`, `1d`) |
| `NODE_ENV` | ❌ | `development` | Set `production` khi deploy |

> Không cần set `DB_PATH`, `UPLOAD_DIR` — đã hardcode trong Dockerfile.

---

## Tài khoản mặc định

| Username | Password | Role |
|----------|----------|------|
| `admin` | `Admin@123` | Toàn quyền (CRUD docs, users) |
| `user` | `User@123` | Đọc, chat, làm quiz |

> **Đổi mật khẩu ngay** sau lần đầu đăng nhập qua API `/api/admin/users`.

---

## API Reference

### Auth
| Method | Endpoint | Mô tả |
|--------|----------|-------|
| POST | `/api/auth/login` | Đăng nhập → JWT token |

### Chat (Bearer token required)
| Method | Endpoint | Mô tả |
|--------|----------|-------|
| POST | `/chat` | AI chat streaming (SSE) |
| GET | `/chat/history/{session_id}` | Lịch sử hội thoại |

### Documents
| Method | Endpoint | Role | Mô tả |
|--------|----------|------|-------|
| GET | `/api/docs` | All | List/search documents |
| GET | `/api/docs/{id}` | All | Chi tiết document |
| POST | `/api/docs` | Admin | Tạo document (JSON) |
| POST | `/api/docs/upload` | Admin | Upload file |
| DELETE | `/api/docs/{id}` | Admin | Xóa document |

### Quiz
| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/quiz?section=&count=` | Lấy câu hỏi |
| POST | `/api/quiz/attempt` | Nộp bài, chấm điểm |
| GET | `/api/quiz/history` | Lịch sử làm quiz |

### Admin
| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/admin/users` | Danh sách users |
| POST | `/api/admin/users` | Tạo user |
| DELETE | `/api/admin/users/{id}` | Xóa user |
| GET | `/api/stats` | Thống kê hệ thống |

### System
| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/health` | Health check |
| GET | `/docs` | Swagger UI |

---

## 5 Phần Nội Dung

| ID | Tên | Ví dụ |
|----|-----|-------|
| 1 | Từ Điển Thuật Ngữ Ops | TPV, Lead, CR%, Onboard, Churn |
| 2 | Quy Trình Chuẩn | SOP Onboarding, Memo nội bộ |
| 3 | Cẩm Nang Xử Lý Sự Cố | Soundbox lỗi, cổng thanh toán |
| 4 | Danh Mục Thiết Bị & Phần Cứng | SB200, mPOS, reset thiết bị |
| 5 | Kiểm Tra Kiến Thức | Quiz trắc nghiệm A/B/C/D |

---

## Thêm nội dung vào Knowledge Base

### Qua API (Admin)

```bash
TOKEN="eyJ..."

# Upload markdown
curl -X POST http://localhost:3000/api/docs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "section": 1,
    "title": "Định nghĩa Churn Rate",
    "content": "## Churn Rate\n\nTỷ lệ merchant ngừng sử dụng dịch vụ...",
    "file_type": "md"
  }'

# Upload file PDF/DOCX
curl -X POST http://localhost:3000/api/docs/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "section=2" \
  -F "title=SOP Xử Lý Khiếu Nại" \
  -F "file=@./sop_khieu_nai.pdf"
```

### Thêm câu hỏi quiz

Hiện tại qua SQLite trực tiếp hoặc extend API. Ví dụ SQL:

```sql
INSERT INTO quiz_questions
  (section, question, option_a, option_b, option_c, option_d, correct_answer, explanation)
VALUES
  (2, 'Thời gian onboarding merchant tối đa là?',
   '1 ngày', '3 ngày', '5 ngày', '7 ngày',
   'B', 'Theo SOP chuẩn: tối đa 3 ngày làm việc');
```

---

## Troubleshooting

| Vấn đề | Nguyên nhân | Giải pháp |
|--------|-------------|-----------|
| `ANTHROPIC_API_KEY not set` | Thiếu env var | Set trên AgentBase dashboard |
| Chat trả lời "không có thông tin" | Chưa có tài liệu | Admin upload tài liệu |
| Container crash khi start | `JWT_SECRET` thiếu | Set env var `JWT_SECRET` |
| Tài liệu mất sau restart | Volume chưa mount | Attach persistent volume `/app/data` |
| 401 Unauthorized | Token hết hạn | Login lại để lấy token mới |
| Upload file thất bại | File quá lớn | Tăng `MAX_FILE_SIZE_MB` |
| `/health` trả 502 | Container chưa start xong | Đợi 30s, check logs |

---

## Kiến trúc kỹ thuật

```
POST /chat
  ↓
FastAPI handler
  ↓
Anthropic Claude (claude-opus-4-5)
  ↓ tool_use loop
  ├── search_knowledge_base()  → SQLite FTS5 full-text search
  ├── get_section_content()    → List documents by section
  ├── get_quiz_questions()     → Random quiz questions
  └── get_document_detail()   → Full document content
  ↓
StreamingResponse (Server-Sent Events)
  ↓
Client (word-by-word streaming)
```

---

## Liên hệ & Hỗ trợ

- **GreenNode AgentBase docs:** [greennode.ai/product/agentbase](https://greennode.ai/product/agentbase)
- **GreenNode support:** 1900 1549
- **Anthropic API docs:** [docs.anthropic.com](https://docs.anthropic.com)
- **Chi tiết kỹ thuật:** Xem `CLAUDE.md`
