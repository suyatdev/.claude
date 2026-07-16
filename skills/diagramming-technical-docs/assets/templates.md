# Mermaid Templates

Fill-in-the-blank starting points. Copy the block, replace the placeholders, delete the
rows you don't need. All render natively in GitHub, VS Code, and Claude Artifacts.

---

## System architecture map

```mermaid
graph TD
    Client[Client / Web App] -->|HTTPS| LB[Load Balancer]
    LB --> App[App Service]
    App --> Cache[(Cache)]
    App --> DB[(Primary DB)]
    App --> Queue[[Message Queue]]
    Queue --> Worker[Background Worker]
    Worker --> DB
```

## API authentication — sequence

```mermaid
sequenceDiagram
    participant U as Client
    participant G as Gateway
    participant A as Auth Service
    participant D as User DB
    U->>G: POST /login (credentials)
    G->>A: verify
    A->>D: lookup user
    D-->>A: user + hash
    A-->>G: signed token
    G-->>U: 200 + session cookie
    Note over A,D: failure path returns 401, no token
```

## Data pipeline / ETL

```mermaid
flowchart LR
    Src[Source System] --> Extract[Extract]
    Extract --> Q{{Validation Queue}}
    Q -->|valid| Transform[Transform]
    Q -->|rejected| DLQ[(Dead-letter Store)]
    Transform --> Load[Load]
    Load --> WH[(Data Warehouse)]
```

## State machine — order lifecycle

```mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> Paid: payment captured
    Pending --> Cancelled: timeout / user cancel
    Paid --> Shipped: dispatched
    Shipped --> Delivered: delivery confirmed
    Paid --> Refunded: refund issued
    Delivered --> [*]
    Cancelled --> [*]
    Refunded --> [*]
```

## Data model — ER diagram

```mermaid
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : "appears in"
    USER {
        uuid id PK
        string email
    }
    ORDER {
        uuid id PK
        uuid user_id FK
        string status
    }
```

## Decision / tradeoff — mind map

```mermaid
mindmap
  root((Decision: X vs Y))
    Option_X
      Pros
        Benefit_1
        Benefit_2
      Cons
        Drawback_1
    Option_Y
      Pros
        Benefit_1
      Cons
        Drawback_1
        Drawback_2
    Deciding_factor
      Constraint_that_breaks_the_tie
```

## Root-cause / troubleshooting — mind map

```mermaid
mindmap
  root((Symptom: slow API))
    Application
      N_plus_1_queries
      Missing_cache
    Database
      Lock_contention
      Missing_index
    Network
      Cross_region_hop
      TLS_handshake_cost
    Infra
      Undersized_instance
```
