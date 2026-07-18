# Cedar Evaluator — Design Spec

## Overview

实现 Cedar 策略评估器，对给定的 `Request` 和 `EntityStore` 求值 `PolicySet`，输出 `AuthorizationResult`。
采用 Rust 的统一 partial-eval 架构：所有求值统一走 `EvalResult = Value | Residual(Expr)` 路径，concrete eval 就是残差为空的特例。

当前为 **CPE (Classic Partial Evaluation)** — 不依赖 schema/typechecker，残差无类型标注。
TPE (Type-aware Partial Evaluation) 在 schema + typechecker 到位后迭代升级。

参考：
- Rust: `cedar-policy-core/src/evaluator.rs`, `authorizer.rs`, `entities.rs`
- Go: `cedar-go/internal/eval/`
- [RFC 0095: TPE](https://github.com/cedar-policy/rfcs/blob/main/text/0095-type-aware-partial-evaluation.md)

---

## New Types (`eval/types.mbt`)

```moonbit
// 求值结果：具体值 或 残差表达式
pub(all) EvalResult = Value(@ast.Value) | Residual(@ast.Expr)

// 实体查找结果
pub(all) Dereference = Data(@ast.Entity) | NoSuchEntity | Residual(@ast.Expr)

// 实体存储 trait — 支持 concrete 和 partial 两种模式
pub(all) trait EntityStore {
  entity(EntityUID) -> Dereference
}

// Map-based 实现（用于测试和简单场景）
pub(all) struct MapEntityStore { entities : Map[EntityUID, Entity] }
impl EntityStore for MapEntityStore { ... }

// EvalError
pub(all) suberror EvalError {
  TypeMismatch(String)             // 类型错误
  IntegerOverflow                  // 整数溢出
  EntityNotFound(String)           // 实体未找到
  InvalidOperator(String)          // 无效运算
  ExtensionNotSupported(String)    // 扩展函数不支持
  SlotNotSupported                 // 模板 slot 不支持
} derive(Debug)
```

---

## File Structure

```
eval/
├── moon.pkg                # 导入 ast
├── types.mbt               # EvalResult, Dereference, EntityStore, EvalError
├── expr_eval.mbt           # eval_expr(Expr) → EvalResult!EvalError
├── operator.mbt            # 具体运算函数 (eval_unary, eval_binary)
├── scope_eval.mbt          # scope_match(ScopeConstraint, Request, EntityStore)
├── policy_eval.mbt         # eval_policy(Policy, Request, EntityStore) → PolicyResult
├── authorizer.mbt          # is_authorized(Request, Policy[], EntityStore) → AuthorizationResult
├── pattern_match.mbt       # wildcard_match(String, Pattern) → Bool
└── eval_wbtest.mbt         # 全部测试
```

---

## Key Algorithms

### 1. Expression Evaluation (`expr_eval.mbt`)

`fn partial_eval_expr(expr: Expr, request: Request, store: EntityStore) -> EvalResult!EvalError`

递归匹配 `Expr` 的 16 种节点：

| Expr 节点 | 求值逻辑 |
|-----------|----------|
| `Lit(v)` | 直接返回 `Value(v)` |
| `Var(kind)` | 从 Request 取对应变量，Principal/Action/Resource 取 EntityUID，Context 取 Map |
| `And(a,b)` | 先求值 a：若 false → 短路 false；若 Residual → 包裹残差；若 true → 继续求值 b |
| `Or(a,b)` | 先求值 a：若 true → 短路 true；若 Residual → 包裹残差；若 false → 继续求值 b |
| `If(c,t,e)` | 先求值 c：若 Bool(true) → 求 t；若 Bool(false) → 求 e；否则 → 包裹残差 |
| `UnaryApp(op,a)` | 先求值 a：若 Value → `unary_op(op, v)`；若 Residual → 包裹残差 |
| `BinaryApp(op,a,b)` | 先求值 a,b：若都 Value → `binary_op(op, v1, v2)`；否则尝试短路，再包裹残差 |
| `GetAttr(e,a)` | 先求值 e：若 Record → 取属性；若 EntityUID → store.entity 后取属性；否则包裹残差 |
| `HasAttr(e,a)` | 类似 GetAttr 但返回 Bool |
| `Like(e,p)` | 先求值 e：若 String → `wildcard_match(s, p)`；否则包裹残差 |
| `Is(e,ty)` | 先求值 e：若 EntityUID → 比较 EntityType；若 typed-unknown → 短路类型比较；否则包裹残差 |
| `Set/Record` | 求值所有元素，全具体 → Value；至少一个残差 → 包裹残差 |
| `ExtensionApp` | MVP 返回 `ExtensionNotSupported` error |
| `Slot` | MVP 返回 `SlotNotSupported` error |
| `Unknown` | 直接返回 `Residual(Unknown)` |

### 2. Operator Functions (`operator.mbt`)

**UnaryOp:**
- `Not`: Bool true → false, false → true；非 Bool → TypeMismatch
- `Neg`: Long n → -n (checked overflow)；非 Long → TypeMismatch
- `IsEmpty`: Set/Record → 检查是否为空；其他 → TypeMismatch

**BinaryOp:**
- `Eq/Ne`: 比较两个 Value 的结构相等性（不同类型直接 false）
- `Less/LessEq/Gt/Ge`: Long 比较 + extension 支持（extension 本期返回 error）
- `Add/Sub/Mul`: 有符号整数运算，checked overflow
- `In`: 单实体 → hierarchy traversal；Set → 遍历成员各自检查；非 Entity → TypeMismatch
- `Contains/ContainsAll/ContainsAny`: Set 操作
- `GetTag/HasTag`: 实体 tag 查找

**短路线索（partial eval 关键优化）：**

| 操作 | 条件 | 结果 |
|------|------|------|
| `Eq(Lit(EntityUID(t1,_)), Unknown(t2,_))` | t1 ≠ t2 | false（类型不同无需知道 id） |
| `Is(Unknown(e1), e2)` | e1.type ≠ e2 | false |
| `In(Unknown(e1), Lit(EntityUID(_)))` | e1.type ∉ e2.hierarchy | false |

### 3. Scope Matching (`scope_eval.mbt`)

`fn scope_match(sc: ScopeConstraint, var: EntityUID, store: EntityStore) -> Bool`

| ScopeConstraint | 匹配逻辑 |
|-----------------|----------|
| `All` | 永远 true |
| `Eq(entity)` | `var == entity` |
| `In(parent)` | hierarchy traversal: var 是否是 parent 的后代（或相等） |
| `InSet(entities)` | var 是否在 entities 数组中 |
| `Is(ty)` | `var.type_ == ty` |
| `IsIn(ty, parent)` | var.type_ == ty 且 var 是 parent 的后代（或相等） |

### 4. Hierarchy Traversal (`scope_eval.mbt`)

实体层次结构用 BFS 遍历（Go 参考实现方式）。`Entities` 维护传递封闭的 ancestor 关系。

`fn is_descendant(uid: EntityUID, ancestor: EntityUID, store: EntityStore) -> Bool`
- 从 uid 开始 BFS 向上追溯 parents
- 使用 Set 去重避免循环
- 若找到 ancestor → true；否则 → false

### 5. Pattern Matching (`pattern_match.mbt`)

`fn wildcard_match(text: String, pattern: Pattern) -> Bool`

双指针回溯算法：
- `*` 匹配任意字符序列（包括空）
- `\*` 匹配字面 `*`（已在 parser 阶段解析到 PatternElem）
- 遍历 text 和 pattern 同步前进
- 遇到 Wildcard 记录回溯点，失配时回溯

### 6. Policy Evaluation (`policy_eval.mbt`)

`fn eval_policy(p: Policy, req: Request, store: EntityStore) -> PolicyResult!EvalError`

```
PolicyResult = Satisfied | False | Residual(Expr) | Error(EvalError)
```

流程：
1. `scope_match(p.principal, req.principal, store)` — 不匹配则 skip
2. `scope_match(p.action, req.action, store)` — 不匹配则 skip
3. `scope_match(p.resource, req.resource, store)` — 不匹配则 skip
4. 按顺序求值所有 conditions：
   - `When`: 求值 body → 若 false 则 skip 该 policy；若 Residual 则累积残差
   - `Unless`: 求值 body → 若 true 则 skip（unless 为真 = 不满足）；若 Residual 则累积残差
5. 所有 condition 都 true → Satisfied；有残差 → Residual(合并)；有 false → False

### 7. Authorizer (`authorizer.mbt`)

`fn is_authorized(req: Request, policies: Array[Policy], store: EntityStore) -> AuthorizationResult`

```
对于每个 policy:
  result = eval_policy(policy, req, store)
  match (policy.effect, result):
    (Permit, Satisfied) → satisfied_permits.add(policy.id)
    (Permit, False)     → false_permits.add(policy.id)
    (Permit, Residual)  → residual_permits.add(policy.id)
    (Permit, Error)     → errors.add(policy.id, error_message)
    (Forbid, Satisfied) → satisfied_forbids.add(policy.id)
    (Forbid, False)     → (无操作)
    (Forbid, Residual)  → residual_forbids.add(policy.id)
    (Forbid, Error)     → errors.add(policy.id, error_message)

Decision:
  若有 satisfied_permit 且无 satisfied_forbid → Allow
  否则 → Deny
```

---

## Data Flow

```
parse_policies(src) → Array[Policy]
  ↓
is_authorized(Request, policies, EntityStore)
  ↓
Evaluator
  ├── scope_match(principal, request.principal, store)
  ├── scope_match(action, request.action, store)
  ├── scope_match(resource, request.resource, store)
  ├── eval_conditions(conditions)
  │     └── partial_eval_expr(expr, request, store)
  │           ├── literal → Value
  │           ├── variable → lookup Request
  │           ├── binary_op → operator.binary_op()
  │           ├── get_attr → record / entity dereference
  │           ├── like → pattern_match.wildcard_match()
  │           └── residual → Residual(expr)
  └── collect → categorize by effect + result
       └── concretize → Decision::Allow/Deny
```

---

## Error Handling

- 求值错误：类型错误、整数溢出、实体未找到 → `EvalError`
- 错误不中止整体求值（跟 Rust 一样 `ErrorHandling::Skip`）
- 错误的 policy 记录到 `AuthorizationResult.errors`
- partial eval 下的残差不视为错误

---

## MVP 边界

- ✅ 基础字面量求值（Bool, Long, String, EntityUID）
- ✅ 变量解析（principal, action, resource, context）
- ✅ 16 种 Expr 节点求值
- ✅ 14 种 BinaryOp + 3 种 UnaryOp
- ✅ Scope 匹配（All, Eq, In, InSet, Is, IsIn）
- ✅ Hierarchy traversal (BFS)
- ✅ Pattern matching (wildcard_match)
- ✅ And/Or/If 短路求值
- ✅ Entity attribute/tag 查找
- ✅ Record attribute 查找
- ✅ 带类型标注的 typed-unknown 短路优化
- ✅ 统一的 PartialValue 返回值（为后续 partial eval 铺路）
- ❌ 扩展函数求值（ip, decimal 等）— 返回 EvalError
- ❌ 模板 Slot — 返回 EvalError
- ❌ Batched evaluator — 后续

---

## Test Strategy

1. **expr_eval_wbtest**: 逐个测试每种 Expr 节点的求值结果
2. **operator_wbtest**: 测试每个 BinaryOp/UnaryOp 的具体运算
3. **scope_eval_wbtest**: 测试 6 种 scope constraint 的匹配
4. **pattern_match_wbtest**: 测试 wildcard_match 各种模式组合
5. **policy_eval_wbtest**: 端到端单策略求值
6. **authorizer_wbtest**: 多策略授权决策（permit/forbid 互动）
