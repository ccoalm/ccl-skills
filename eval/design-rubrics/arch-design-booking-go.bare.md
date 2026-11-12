# 会议室预约 技术设计

## 接口

- POST /rooms/{id}/bookings：创建预约，入参开始和结束时间。
- POST /bookings/{id}/confirm：确认预约。
- POST /bookings/{id}/cancel：取消预约。
- PUT /rooms/{id}/status：管理员修改会议室状态。

## 数据表

rooms(id, name, status)；bookings(id, room_id, user_id, start_at, end_at, status, created_at)。

## 流程

用户选择时间段后创建预约，页面提示在 10 分钟内确认。定时任务每分钟扫描一次预约表，给即将开始的预约调用提醒服务。

## 上线

先给一个办公区试用两周，收集反馈后全量。
