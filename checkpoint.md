# Mooncedar — Checkpoint

MoonBit 实现的 Cedar 策略语言解析器、评估器与授权器。`jaredzhou/mooncedar@0.1.1`

## 参考

| 来源 | 地址 |
|------|------|
| Cedar 官方规范 | https://www.cedarpolicy.com |
| Rust 实现 (AWS) | https://github.com/cedar-policy/cedar |
| Go 实现 | https://github.com/cedar-policy/cedar-go |

## 项目结构

```
mooncedar/
├── moon.mod                    # 模块定义
├── moon.pkg                    # 根包导入 (evaluator, ast, parser, debug, json)
├── types.mbt                   # 公共 API: type aliases (Expr, Policy, Request, Value, ...)
│                                #   + builder 重导出 (expr_bool, expr_unknown, default_policy, ...)
│                                #   + parse_policies, stringify, stringify_expr
├── authorizer.mbt              # 授权 API: evaluate / reauthorize / concretize / is_authorized
│                                #   PartialAuthorizationAnswer (satisfied + residuals + errors)
│                                #   substitute_unknowns, Decision, AuthorizationResult
├── authorizer_wbtest.mbt       # 授权器白盒测试: is_authorized(6) + evaluate(3) + concretize(1) + reauthorize(10)
├── entity_store.mbt            # MapEntityStore + EntityStore impl + ToJson/FromJson
│                                #   + cedar_*_json + new_map_store + RequestJSON + to_request_json
├── entity_store_wbtest.mbt     # MapEntityStore JSON 测试 (7) + RequestJSON roundtrip (3)
├── example_wbtest.mbt          # 端到端示例测试 (3) — 从字符串解析 policy + entities
├── .claude/skills/using-mooncedar/SKILL.md  # 集成 skill
├── ast/
│   ├── moon.pkg                # 导入 (json, debug)
│   ├── types.mbt               # 纯 AST 类型 (EntityUID, EntityType, Pattern, Type, Value, PartialValue, Entity)
│   ├── expr.mbt                # 表达式 AST (Literal, VarKind, UnaryOp, BinaryOp, Expr, Unknown) + builder
│   ├── policy.mbt              # 策略 AST (Policy, ScopeConstraint, Condition, PolicyEffect) + builder
│   ├── validator.mbt           # 策略验证器 (ValidationError, validate_policy)
│   ├── builder_wbtest.mbt      # Builder 测试
│   └── validator_wbtest.mbt    # 验证器测试
├── evaluator/
│   ├── moon.pkg                # 导入 (ast, debug, json)
│   ├── types.mbt               # EntityStore(open trait), EvalError, Dereference, EntityUIDEntry, Context, Request
│   ├── pattern_match.mbt       # wildcard_match — 双指针回溯
│   ├── scope_eval.mbt          # scope_match + is_descendant BFS
│   ├── operator.mbt            # eval_unary + eval_binary
│   ├── expr_eval.mbt           # eval_expr — 16 种 Expr 递归求值 + try_eval + get_attr_value + value_to_expr
│   ├── policy_eval.mbt         # eval_policy — scope + conditions + 残差合并
│   └── eval_wbtest.mbt         # 评估器白盒测试 (117 个) — CPE 语义, entity hierarchy, policy eval
└── parser/
    ├── moon.pkg                # 导入 (ast, debug)
    ├── lexer.mbt               # tokenize — 词法分析
    ├── expr_parser.mbt         # parse_expr — 递归下降
    ├── parser.mbt              # parse_policies — 策略解析
    ├── stringify.mbt           # AST → Cedar 源码
    ├── expr_wbtest.mbt         # 表达式解析测试
    ├── parser_wbtest.mbt       # 策略解析测试
    └── stringify_wbtest.mbt    # Stringify inspect 测试
```

**总代码量**: ~8000 行 | **测试**: 572 个 (572 通过)

## 已完成

### 公共 API ✓
- [x] `types.mbt` — `pub type` 别名: Expr, Policy, Value, Request, Context, EntityUIDEntry, EvalError, ParseError, ...
- [x] Builder 重导出: `expr_bool`, `expr_str`, `expr_euid`, `expr_principal`, `expr_unknown`, `expr_if`, `expr_record`, `default_policy`, ...
- [x] 用户只需 `import { "jaredzhou/mooncedar" }` 即可获得所有常用类型和 builder

### AST 类型系统 ✓
- [x] `Expr` — 完整 Cedar 表达式 AST (18 种节点)
- [x] `Unknown(String, Option[Type])` — 带可选类型标注
- [x] `PartialValue` — `Value(Value) | Residual(Expr)` 统一 partial eval 返回类型
- [x] `Policy` / `ScopeConstraint` / `ConditionKind` / `Condition` / `PolicyEffect`
- [x] 基础类型: EntityUID, EntityType, Name, Pattern, Type, Value, Entity

### Builder 模式 ✓
- [x] Expr 构造器 + 链式方法 (22 个)，命名统一 `expr_` 前缀
- [x] Policy builder: `default_policy()`, `.permit()`, `.forbid()`, scope 方法, `.when_()`, `.unless()`

### 解析器 ✓
- [x] 词法分析: 关键字(11), 运算符(11)
- [x] 表达式递归下降，Cedar 语法规范优先级
- [x] 策略解析: 多策略, 注解, effect, scope, conditions, InSet
- [x] 每策略解析后立即执行语义验证

### Stringify ✓
- [x] AST → Cedar 源码，优先级最小括号化 (9 级)

### 策略验证器 ✓
- [x] `ValidationError` / `validate_policy` / `validate_policies`

### 评估器 ✓
- [x] `pub(open) trait EntityStore` — 跨包可插拔实体存储
- [x] `EntityUIDEntry` / `Context` / `Request` — PARC + partial eval 支持
- [x] `concrete_uid`, `unknown_uid`, `concrete_context`, `unknown_context`, `partial_context`
- [x] `wildcard_match` — 双指针回溯
- [x] `scope_match` + `is_descendant` — BFS 层次遍历
- [x] `eval_unary` (3) + `eval_binary` (12) — checked overflow
- [x] `eval_expr` — 18 种 Expr 递归求值，And/Or 短路 (匹配 Rust CPE 语义)
- [x] `get_attr_value` — Context::Partial 可投影 Unknown
- [x] `value_to_expr` — Value 转 Expr，含 Record 展开
- [x] `eval_policy` — scope + conditions 求值，Unknown PARC 生成残差
- [x] `try_eval` — 残差侧错误抑制

### 授权器 ✓
- [x] `evaluate` → `PartialAuthorizationAnswer`
- [x] `reauthorize` — 扩充 store + mapping 重求值
- [x] `concretize` → Allow/Deny
- [x] `is_authorized` — 便捷封装
- [x] `substitute_unknowns` — mapping 替换

### Reauthorize 测试 (4 类 Unknown) ✓
- [x] **Cat 1: PARC unknown** — mapping 解析/不解析
- [x] **Cat 2: Context attr unknown** — 可投影/不可投影/不存在 key
- [x] **Cat 3: Policy expr unknown** — mapping 解析/不解析
- [x] **Cat 4: Entity missing** — in 操作符/仍缺失/forbid/satisfied 前传

### Entity store ✓
- [x] `MapEntityStore` — 根包默认实现，`pub(all)` + `ToJson`/`FromJson`
- [x] `new_map_store()` — 空 store 构造器
- [x] `RequestJSON` — JSON DTO: 支持字符串/对象 PARC 格式
- [x] `to_request_json()` / `to_request()` — Request ↔ JSON 双向转换
- [x] `cedar_entity_from_json` / `cedar_value_from_json` / `cedar_value_from_object`

### JSON 序列化 ✓
- [x] `EntityUID` — 手动 `ToJson`/`FromJson`，`type_` ↔ `"type"`
- [x] `Entity` / `Value` / `Name` / `EntityType` — derive
- [x] `MapEntityStore` — 手动 impl，数组格式

### 已验证 ✓
- [x] `moon test`: 572/572 通过

### 待实现

1. **模板支持** — `Expr::Slot` 模板实例化
2. **扩展函数** — IP, decimal 等实际求值
3. **TPE** — schema + type checker 后，typed Unknown 短路优化

## 设计约定

- **命名**: `expr_*` 为表达式构造器 (`expr_bool`, `expr_principal`, `expr_unknown`); 方法为链式 `.eq()`, `.access()`, `.has_tag()` 等
- **Builder**: 方法定义在类型上 (无 wrapper)
- **包结构**: `ast/` (语言定义) → `evaluator/` (求值 trait) → 根 `authorizer.mbt` (授权 API) + 根 `entity_store.mbt` (实体存储)
- **公共 API**: `types.mbt` 通过 `pub type` 别名 + builder 包装函数统一导出，用户无需 import 子包
- **求值**: `PartialValue` 统一返回; store-dependent 运算内联; `try/catch` 边界捕获
- **EntityStore**: `pub(open)` trait，默认 `MapEntityStore` 在根包
- **策略迭代**: `evaluate` / `is_authorized` 接受 `Iter[Policy]`
- **测试字符串**: 用 `#|content|` 单行原始字符串
