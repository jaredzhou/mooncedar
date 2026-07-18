Partial Eval 中 Unknown 出现的所有情况
  
  总览

                          ┌── 1. Request 层 (用户主动)
                          │     principal / action / resource / context 整体
                          │
                          ├── 2. Context 属性层 (用户主动)
  Unknown 的来源 ──────────┤     context 中的单个属性值为 unknown
                          │
                          ├── 3. 策略表达式层 (用户主动)
                          │     策略中显式写 unknown("name")
                          │
                          ├── 4. Entity 缺失 (数据缺失，自动生成)
                          │     partial mode 下 entity store 查不到某个 UID
                          │
                          └── 5. Entity attr/tag 值为 unknown (数据缺失或用户构造)
                                entity 存在，但属性/标签的值是 unknown

  ---
  1. Request 层 — PARC 未知
  
  来源： 用户主动构造 partial request

  ┌──────────────┬─────────────────────────────────┬──────────────────┐
  │ Unknown 名字 │            产生方式             │     代码位置     │
  ├──────────────┼─────────────────────────────────┼──────────────────┤
  │ "principal"  │ EntityUIDEntry::unknown()       │ request.rs:70-81 │
  ├──────────────┼─────────────────────────────────┼──────────────────┤
  │ "action"     │ EntityUIDEntry::unknown()       │ 同上             │
  ├──────────────┼─────────────────────────────────┼──────────────────┤
  │ "resource"   │ EntityUIDEntry::unknown()       │ 同上             │
  ├──────────────┼─────────────────────────────────┼──────────────────┤
  │ "context"    │ Context 为 None（不传 context） │ evaluator.rs:353 │
  └──────────────┴─────────────────────────────────┴──────────────────┘

  // 例子
  let request = Request::new_with_unknowns(
      EntityUIDEntry::unknown(),           // "principal" → unknown
      EntityUIDEntry::unknown(),           // "action"    → unknown
      EntityUIDEntry::unknown(),           // "resource"  → unknown
      None,                                // "context"   → unknown
  );

  reauthorize 替换方式： 固定 key 名
  {"principal" → entity_uid, "action" → entity_uid, "resource" → entity_uid, "context" → record}

  ---
  2. Context 属性层 — 单属性未知
  
  来源： 用户主动构造带 unknown 的 context

  // 例子
  let context = Context::from_pairs([
      ("c", RestrictedExpr::unknown(Unknown::new_untyped("c"))),     // "c" → unknown
      ("d", RestrictedExpr::unknown(Unknown::new_untyped("d"))),     // "d" → unknown
  ], exts).unwrap();

  Partial eval 时：
  - 可投影：context.c → unknown("c")（被投影出来）
  - 不可投影：context.key → record(...).key（整体 residual）
  - 不存在的 key：context.foo → Error

  reauthorize 替换方式： 按属性名
  {"c" → true, "d" → 10}

  相关测试： evaluator.rs:5139-5270 (partial_contexts1-4, partial_context_fail)

  ---
  3. 策略表达式层 — 显式 unknown("name")
  
  来源： 策略中用户显式写 unknown("name") 函数调用

  permit(principal, action, resource) when {
      unknown("threshold") > 10 && unknown("flag")
  };

  通过 partial_evaluation 扩展的 unknown 函数实现 (extensions/partial_evaluation.rs:18-30)：

  fn create_new_unknown(..., str: SmolStr) -> ExtensionOutputValue {
      ExtensionOutputValue::Unknown(Unknown::new_untyped(str))
  }

  Partial eval 时产生 ExprKind::Unknown AST 节点，保留在 residual 中。

  reauthorize 替换方式： 按 unknown 名字
  {"threshold" → 15, "flag" → true}

  ---
  4. Entity 缺失 — partial entity store 自动生成
  
  来源： 数据缺失，系统自动生成。需要 Entities::partial() 模式。

  // entities.rs:94-108
  pub fn entity(&self, uid: &EntityUID) -> Dereference<'_, Entity> {
      match self.entities.get(uid) {
          Some(e) => Dereference::Data(e),
          None => match self.mode {
              Mode::Concrete => Dereference::NoSuchEntity,        // → Error
              Mode::Partial => Dereference::Residual(             // → 自动生成 typed unknown
                  Expr::unknown(Unknown::new_with_type(
                      uid.to_smolstr(),                           // 名字 = entity UID 字符串
                      Type::Entity { ty: uid.entity_type() },     // 带 entity type 标注
                  ))
              ),
          },
      }
  }

  涉及的运算符和位置：

  ┌─────────────┬───────────────────────────────────────────────────┬──────────────────────┐
  │   运算符    │                       行为                        │         代码         │
  ├─────────────┼───────────────────────────────────────────────────┼──────────────────────┤
  │ in          │ unknown("uid").in(parent) — residual              │ evaluator.rs:589     │
  ├─────────────┼───────────────────────────────────────────────────┼──────────────────────┤
  │ hasTag      │ unknown("uid").hasTag("tag") — residual           │ evaluator.rs:651     │
  ├─────────────┼───────────────────────────────────────────────────┼──────────────────────┤
  │ getTag      │ unknown("uid").getTag("tag") — residual           │ evaluator.rs:631     │
  ├─────────────┼───────────────────────────────────────────────────┼──────────────────────┤
  │ . (GetAttr) │ unknown("uid").attr — residual                    │ evaluator.rs:954     │
  ├─────────────┼───────────────────────────────────────────────────┼──────────────────────┤
  │ is          │ is_entity_type(unknown("uid"), "Type") — residual │ evaluator.rs:733-742 │
  └─────────────┴───────────────────────────────────────────────────┴──────────────────────┘

  reauthorize 替换方式： 按 entity UID 字符串
  {"Test::\"missing\"" → entity_uid_value}

  相关测试： evaluator.rs:1324-1456 (partial_entity_stores_*)

  ---
  5. Entity 存在，attr/tag 值为 unknown
  
  来源： Entity 在 store 中存在，但属性值的表达式含 unknown（数据不完整或用户故意构造）

  // 构造一个 entity，members 属性存在但值是 unknown
  let entity = Entity::new(
      uid,
      [
          ("members", RestrictedExpression::new_unknown("partial_members")),  // ← unknown
          ("owners",  RestrictedExpression::new_entity_uid(...)),             // ← 具体值
      ].into(),
      ...
  );

  Entity 内部存储结构 (entity.rs:482,498)：
  pub struct Entity {
      attrs: BTreeMap<SmolStr, PartialValue>,  // 值可以是 PartialValue::Residual
      tags:  BTreeMap<SmolStr, PartialValue>,  // 同上
  }
  
  求值时 (evaluator.rs:957-964)：
  Dereference::Data(entity) => entity
      .get(attr)                                   // attr 存在 → Some
      .map(|pv| match pv {
          PartialValue::Value(_) => Ok(...),       // 值具体
          PartialValue::Residual(e) => match e.expr_kind() {
              ExprKind::Unknown(u) => self.unknown_to_partialvalue(u),  // ← 尝试 mapper
              _ => Ok(...),                        // 其他 residual
          },
      })  
      .ok_or_else(|| entity_attr_does_not_exist(...))  // attr 不存在 → Error

  reauthorize 替换方式： 按 unknown 名字
  {"partial_members" → UserGroup::"1"}

  相关测试： api/tpe.rs:2036 (test_batched_evaluation_error_partial_entity)

  ---
  Unknown 类型标注对比
  
  ┌────────────────────────┬───────────────────────────────────────────┬─────────────────────┐
  │          来源          │           有 type_annotation？            │      标注内容       │
  ├────────────────────────┼───────────────────────────────────────────┼─────────────────────┤
  │ PARC unknown           │ 可选（EntityUIDEntry::unknown_with_type） │ Type::Entity        │
  ├────────────────────────┼───────────────────────────────────────────┼─────────────────────┤
  │ Context 属性 unknown   │ 无（Unknow::new_untyped）                 │ —                   │
  ├────────────────────────┼───────────────────────────────────────────┼─────────────────────┤
  │ 策略 unknown("x")      │ 无（Unknow::new_untyped）                 │ —                   │
  ├────────────────────────┼───────────────────────────────────────────┼─────────────────────┤
  │ Entity 缺失            │ 有（Unknown::new_with_type）              │ Type::Entity { ty } │
  ├────────────────────────┼───────────────────────────────────────────┼─────────────────────┤
  │ Entity attr 值 unknown │ 取决于用户构造时是否带类型                │ —                   │
  └────────────────────────┴───────────────────────────────────────────┴─────────────────────┘

  ---
  最终结论

  5 种 unknown 来源，按性质分两类：

  ┌──────────┬───────────────────────────────────────────────────────────────────────┐
  │   性质   │                                 来源                                  │
  ├──────────┼───────────────────────────────────────────────────────────────────────┤
  │ 用户主动 │ ① PARC unknown ② Context 属性 unknown ③ 策略表达式 unknown("name")    │
  ├──────────┼───────────────────────────────────────────────────────────────────────┤
  │ 数据缺失 │ ④ Entity 缺失（自动生成 typed unknown）⑤ Entity attr/tag 值为 unknown │
  └──────────┴───────────────────────────────────────────────────────────────────────┘

  2 种不可通过 reauthorize 修复的"失败"：

  - Entity 缺失 + Mode::Concrete → NoSuchEntity error（不是 unknown）
  - Entity/Record 属性不存在 → *_attr_does_not_exist error（不是 unknown）

  所有 unknown，不论来源，reauthorize 都按名字替换。