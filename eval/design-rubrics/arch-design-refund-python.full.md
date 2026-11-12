# 订单部分退款 技术设计

## 领域模型与不变量

1. 退款总额上限：同一订单，处理中和已成功的退款金额之和不得超过实付金额，两笔申请并发到达时也必须成立。保证方式：创建退款时在同一事务内锁住订单行（SELECT ... FOR UPDATE），重新汇总后再插入；集成测试 concurrent_refunds_never_exceed_paid 并发发起两笔合计超额的申请，断言只有一笔成功。
2. 一次申请至多一笔退款：客户端重试和渠道重复回调都不会产生或入账第二笔退款。保证方式：refunds.request_id 上建唯一索引，重复请求直接返回已有退款；回调按 channel_refund_no 唯一索引去重。
3. 终态不可变：退款进入成功或失败之后不再变化，晚到或乱序的回调被忽略。保证方式：状态更新用条件更新 UPDATE refunds SET status=? WHERE id=? AND status='processing'，影响行数为 0 即丢弃；单测 late_callback_is_ignored 覆盖先成功后处理中的顺序。
4. 已关闭订单不可退款：订单处于已关闭状态时拒绝创建退款。保证方式：在第 1 条的同一把行锁内校验订单状态，不满足时返回错误码 ORDER_CLOSED；单测 refund_rejected_when_order_closed。

## 分层与依赖方向

路由层调应用服务，应用服务调领域层；仓储实现领域层定义的接口。依赖只朝里指：领域层不 import SQLAlchemy、FastAPI 或渠道 SDK。

## 运行时

- 请求路径只做校验、落库和入队；调用支付渠道和通知账务都放到 Celery worker 里执行，不在 async 路由里做阻塞调用。
- 数据库引擎、渠道客户端和队列生产者都在 create_app 里装配并注入，模块导入时不发起任何网络连接，也不留全局客户端。
- 账务通知走 outbox 表加 worker 投递，账务不可用时重试。
