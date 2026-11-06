# PRD：会议档期 `.ics` 导出 / 分享

- 文档版本：v1.0
- 日期：2026-11-06
- 状态：待评审
- 目标版本：下一版本（建议 1.9）

## 1. 背景

OffTime 已经能根据多城市工作时段生成会议推荐档期，并保存到「推荐记录」。但用户拿到合适档期后，仍需手动把时间重新录入系统日历，或复制文字发给同事，推荐结果没有真正进入日常工作流。

本需求补齐最后一步：把单个会议档期导出为标准 `.ics` 文件，通过系统分享面板保存到日历、发送给同事，或导入 Google Calendar / Outlook。

## 2. 目标

- 用户从推荐档期或推荐记录中，一键分享单个会议日程。
- 导出的日程在 Apple Calendar、Google Calendar、Outlook 中显示正确的绝对时间、时长和参与城市本地时间。
- 不申请日历权限、不上传数据、不依赖网络。
- 旧版本保存的会议记录仍可正常分享；缺少时区数组时优先恢复唯一匹配，无法确定才安全降级。

## 3. 非目标

- 不做批量导出多个档期。
- 不做重复会议、周期性日程。
- 不做会议邀请、RSVP、参与人邮箱或组织者信息。
- 不直接写入系统日历，不引入 EventKit 和日历权限。
- 不做会议编辑、取消通知或视频会议链接。
- 不在 `.ics` 中加入 `VALARM` 或任何提前提醒，本版本不提供提醒时间选择。

## 4. 用户场景

1. 用户在推荐档期详情中选好开始时间，直接分享给同事或保存到日历。
2. 用户已把档期加入推荐记录，之后从记录列表再次分享。
3. 用户升级前保存的旧会议没有参与城市时区字段，仍能导出，并从已保存城市或内置目录恢复每个城市的时区。
4. 会议跨时区、跨日期或跨夏令时切换，分享后的日历时间仍然正确。

## 5. 入口与流程

### 5.1 推荐档期详情

- 在 `SlotDetailSheet` 底部操作栏增加「分享日程」按钮，与「添加到推荐记录」同一行。
- 「分享日程」位于左侧，使用白色背景、蓝色边框和蓝色文字；「添加到推荐记录」保持主按钮样式。
- 使用当前选中的开始时间、会议时长和已选参与城市生成 `.ics`。
- 分享不自动加入推荐记录；用户仍可通过底部「添加到推荐记录」保存。
- 分享完成后保留当前档期详情，便于用户继续添加到推荐记录。

### 5.2 推荐记录列表

- 不增加编辑或更多菜单按钮，保持记录 Cell 简洁。
- 左滑记录显示删除操作，继续沿用现有删除确认流程。
- 长按记录生成 `.ics` 并弹出系统分享面板。

### 5.3 分享流程

1. 生成临时 `.ics` 文件。
2. 用现有 `ShareSheet` 包装 `UIActivityViewController`，分享文件 URL。
3. 分享面板关闭后清理临时文件。
4. 生成或分享失败时弹出错误提示，不影响当前页面状态。

## 6. 功能需求

| ID | 需求 | 优先级 |
| --- | --- | --- |
| FR-1 | 支持从推荐档期详情分享单个 `.ics` | P0 |
| FR-2 | 支持从推荐记录列表分享单个 `.ics` | P0 |
| FR-3 | 使用 UTC 写入 `DTSTART` / `DTEND`，保证跨时区正确 | P0 |
| FR-4 | 描述中列出各参与城市的本地起止时间和 UTC 偏移 | P0 |
| FR-5 | 旧记录缺少城市时区时优先恢复唯一匹配，无法唯一确定才安全降级 | P0 |
| FR-6 | `.ics` 遵循 RFC 5545，支持中文、转义和折行 | P0 |
| FR-7 | 中英文文案跟随 App 当前语言 | P1 |
| FR-8 | 分享失败、文件生成失败有明确提示 | P1 |

## 7. `.ics` 内容规范

### 7.1 日历结构

```text
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//OffTime//Meeting Planner//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:<meeting-id>@offtime.lt
DTSTAMP:<生成时间，UTC>
DTSTART:<开始时间，UTC>
DTEND:<结束时间，UTC>
SUMMARY:<会议标题>
DESCRIPTION:<多行描述>
STATUS:CONFIRMED
TRANSP:OPAQUE
SEQUENCE:0
END:VEVENT
END:VCALENDAR
```

- 时间格式为 `yyyyMMdd'T'HHmmss'Z'`，固定使用 UTC。
- 不写 `VTIMEZONE`，避免 IANA 时区数据库差异导致部分客户端解析失败。
- 已保存记录使用稳定 UID：`<MeetingModel.id>@offtime.lt`。
- 未保存的推荐档期使用一次性 UID：`<UUID>@offtime.lt`。
- 使用 CRLF 换行；文本按 UTF-8 编码，不写 BOM。

### 7.2 标题

- 标题只展示完整城市列表，例如：`上海、伦敦、纽约、东京`。
- 不使用「等 N 个城市」的省略写法。
- 不添加「OffTime 会议」或「OffTime Meeting」前缀。
- 英文使用对应英文城市名和英文连接词。

### 7.3 描述

```text
时长：60 分钟
上海（UTC+08:00）：11 月 7 日 15:30–16:30
伦敦（UTC+00:00）：11 月 7 日 07:30–08:30
```

- 每个参与城市一行，显示城市名、UTC 偏移、当地日期和时间。
- 不显示工作时段、提醒、个人身份信息。
- 旧记录缺少时区数组时，优先从用户已保存城市和内置城市目录恢复每个城市的时区，正常列出各城市日期时间。
- 只有城市名称存在多个时区且无法唯一确定时，才降级显示本地时间和参与城市名称。

### 7.4 转义与折行

- 转义反斜杠、分号、逗号和换行。
- 任意物理行不超过 75 个八位字节；按 UTF-8 字节折行，不能截断中文等多字节字符。
- 生成结果应能被 Apple Calendar、Google Calendar、Outlook 正常解析。

## 8. 数据与兼容

- 在 `MeetingModel` 增加可选数组 `participantTimezoneIds: [String]?`，与 `participantNames` 顺序一致；新记录写入，旧记录为 `nil`。
- 新保存的会议在 `MeetingView.addMeeting` 中写入所选参与城市的时区 ID。
- 旧记录该字段为空：分享时优先按已保存城市和内置城市目录补全唯一时区；歧义城市不做猜测，降级为本地时间。
- 字段必须使用可选值或默认值，确保 SwiftData 旧 store 可以轻量迁移。
- 增加旧 store 升级测试：升级后旧会议可读取、可分享、可删除。
- 不改变现有 JSON 导入导出格式；该字段只属于 SwiftData 会议记录。

## 9. 交互与文案

新增本地化 key（中英文同步）：

| Key | 中文 | 英文 |
| --- | --- | --- |
| `meeting.share.action` | 分享日程 | Share Event |
| `meeting.share.failed.title` | 无法分享日程 | Unable to Share Event |
| `meeting.share.failed.message` | 生成日历文件失败，请稍后重试。 | Couldn’t create the calendar file. Please try again. |
| `meeting.ics.summary.empty` | 会议 | Meeting |
| `meeting.ics.duration` | 时长：%d 分钟 | Duration: %d min |
| `meeting.ics.participant` | %@（%@）：%@ | %@ (%@): %@ |

- 分享按钮需要 VoiceOver 标签，不能只依赖图标。
- 分享面板使用系统 UI，不新增自定义弹窗。
- iPad 上由系统分享面板自行处理 popover。

## 10. 技术方案

- 新增 `MeetingCalendarExportService`，负责把会议数据转换为 `.ics` 字符串并写入临时文件。
- 生成器保持纯函数化，输入为会议值类型，输出为字符串/文件 URL，方便单元测试。
- UI 层只负责收集数据、调用服务、展示 `ShareSheet` 或错误提示。
- 临时文件放在 `FileManager.default.temporaryDirectory`，文件名使用 ASCII：`OffTime-Meeting-20261107-1530.ics`。
- 分享面板关闭后删除临时文件；异常退出时下次启动清理过期文件。
- 不引入第三方库。

建议改动文件：

- `offtime/offtime/Services/MeetingCalendarExportService.swift`（新增）
- `offtime/offtime/Views/MeetingView.swift`
- `offtime/offtime/Views/MeetingListView.swift`
- `offtime/offtime/Models/SwiftDataModels.swift`
- `offtime/offtime/Resources/en.lproj/Localizable.strings`
- `offtime/offtime/Resources/zh-Hans.lproj/Localizable.strings`
- `offtime/offtimeTests/MeetingCalendarExportServiceTests.swift`（新增）

## 11. 验收标准

1. 从推荐档期详情分享后，系统分享面板出现 `.ics` 文件。
2. 从推荐记录分享后，系统分享面板出现 `.ics` 文件。
3. 文件导入 Apple Calendar 后，开始时间、结束时间和时长与 App 内一致。
4. 同一文件在 Google Calendar、Outlook 中导入后，绝对时间一致。
5. 跨时区会议描述中，各城市本地日期和时间正确。
6. 跨夏令时切换的会议，开始和结束的绝对时间正确。
7. 中文城市名、逗号、分号、换行和长描述均正确转义与折行。
8. 旧版本会议记录可以分享，不崩溃，不出现错误时区。
9. 分享过程不弹出日历权限请求，不发起网络请求。
10. 中英文环境下按钮、错误提示和 `.ics` 文案正确。

## 12. 测试计划

### 单元测试

- UTC 时间格式化。
- 时长计算和跨日会议。
- 跨夏令时会议。
- 城市时区偏移格式化。
- 中文和特殊字符转义。
- 75 字节折行。
- 旧记录时区唯一匹配恢复、歧义时区降级输出。
- UID 稳定性和唯一性。

### UI / 手工测试

- 推荐档期详情分享。
- 推荐记录左滑删除、长按分享。
- iPhone / iPad 分享面板。
- 中文 / 英文。
- 旧数据升级后分享。
- 分享失败提示。

## 13. 指标

- 会议分享点击次数 / 推荐记录数量。
- `.ics` 生成失败率。
- 分享后再次分享比例。
- 崩溃率和相关日志。

当前项目没有第三方统计 SDK，本版本不引入；先通过 OSLog 和 TestFlight 反馈验证，后续再补埋点。

## 14. 风险

- 不同日历客户端对 RFC 5545 的兼容度不同：统一使用 UTC 和标准字段降低风险。
- 旧记录没有城市时区：优先唯一匹配恢复；歧义时不猜测，明确降级。
- SwiftData 新增字段迁移：必须用旧 store 做升级测试。
- 未保存档期的 UID 是一次性的：重复分享可能生成多个独立日历事件，符合一次性分享预期。
- 临时文件生命周期：分享面板关闭后清理，避免占空间。

## 15. 排期估算

- 生成器与单元测试：1–1.5 天
- 数据模型与旧数据兼容：0.5–1 天
- UI 入口与分享流程：1 天
- 本地化、测试与回归：1 天
- 总计：约 3.5–4.5 个开发日

## 16. 已确认

- 分享按钮文案使用「分享日程」。
- 标题直接展示全部参与城市，不使用「等 N 个城市」，也不加 OffTime 前缀。
- 不添加日历提醒，不提供「提前多久提醒」选项。
- 后续可单独评审是否增加「复制日程摘要」入口。
