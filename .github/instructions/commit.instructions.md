---
applyTo: "**"
---
# Commit Message 指引

## Conventional Commit 標準
遵循 [Conventional Commits](https://www.conventionalcommits.org/) 規範：

```
<type>: <description>

[optional body]
```

### Type 類型
- `feat`: 新功能
- `fix`: 修復 bug
- `refactor`: 重構（不影響功能）
- `docs`: 文件變更
- `style`: 格式調整（不影響程式邏輯）
- `test`: 測試相關
- `chore`: 建置、工具、依賴更新

## 產生原則
**根據「做了什麼事」來撰寫，而非單純描述程式碼變更**

❌ 錯誤：`修改 TransactionForm.vue 和 api.ts`  
✅ 正確：`feat: 新增自然語言輸入記帳功能`

## 語言
- 使用**繁體中文**撰寫 commit message
- 技術術語可維持英文 (如 API, Vue, TypeScript)

## 範例
```
feat: 新增收據 AI 辨識功能

- 整合 Azure OpenAI Vision API
- 新增 QRCode 解析邏輯
- 支援台灣電子發票格式
```

```
fix: 修正發票號碼格式化錯誤

台灣電子發票號碼現在會正確顯示為 XX-XXXXXXXX 格式
```
