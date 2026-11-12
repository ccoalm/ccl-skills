# 拆分通知服务 技术设计

## 服务

新建 notify-service，Node.js 20 + TypeScript + Fastify。订单服务在下单、发货、退款时调用它的接口。

## 接口

- POST /events：接收订单服务的事件。
- GET /preferences/{userId}：读取通知设置。
- PUT /preferences/{userId}：修改通知设置。

## 数据表

preferences(user_id, channel, enabled, contact)；deliveries(id, user_id, channel, template, status, created_at)。

## 流程

通知服务收到事件后查模板和用户设置，调用短信或邮件供应商发送，把结果写入 deliveries。

## 上线

先接下单事件，观察一周后再接发货和退款事件。
