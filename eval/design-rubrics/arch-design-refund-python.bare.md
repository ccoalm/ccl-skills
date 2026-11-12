# 订单部分退款 技术设计

## 接口

- POST /orders/{id}/refunds：发起退款，入参金额和原因，返回退款单号。
- POST /callbacks/refund：接收支付渠道的退款结果。
- GET /orders/{id}/refunds：查询退款列表。

## 数据表

refunds(id, order_id, amount, status, reason, created_at, updated_at)，status 取 processing / succeeded / failed。

## 流程

收到退款请求后写一条退款记录，调用支付渠道的退款接口，返回退款单号。渠道回调到达后更新退款记录的状态。退款成功后给账务系统发一条消息。

## 上线

先在测试环境联调渠道沙箱，再灰度到 10% 的订单。监控退款成功率和回调延迟。
