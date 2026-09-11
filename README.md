# IPaymentQueue

The interface of [PaymentQueue](https://github.com/uniteum/paymentqueue): idempotent ERC-20 payout
queues, made by anyone for themselves.

A queue pays each payment id at most once, from a float of one ERC-20 token that anyone can top up.
A payment the float cannot cover waits in line until it can, and one the token refuses is recorded
as failed without holding up the payments behind it. The caller chooses each payment's id, and it is
the idempotency key: submitting the same payment again, after a lost response or a retry, never pays
twice.

Depend on this repository rather than on the implementation when you only need to call a queue.

## Contents

- **[IPaymentQueue.sol](IPaymentQueue.sol)** — the queue surface: `pay`, `processPayments`,
  `withdraw`, `statusOf`, `queued`, `owner`, `token`, and the typed factory calls `make`, `made` and
  `encode`.

The factory surface underneath — `proto`, the bytes forms of `make` and `made`, and `zzInit` — comes
from [IPrototype](https://github.com/uniteum/iproto).

## Installation

### Foundry

```bash
forge install uniteum/ipaymentqueue
```

### Git submodule

```bash
git submodule add https://github.com/uniteum/ipaymentqueue lib/ipaymentqueue
```

Then remap it, alongside the ERC-20 interfaces it imports:

```
ierc20/=lib/ierc20/
ipaymentqueue/=lib/ipaymentqueue/
```

## Usage

```solidity
import {IPaymentQueue} from "ipaymentqueue/IPaymentQueue.sol";

// Make your own queue for a token, or fetch the one you already made.
IPaymentQueue queue = prototype.make(token, 0);

// Pay once per id. A repeat is a no-op, whatever happened to the first call.
IPaymentQueue.Status status = queue.pay(id, recipient, amount);
```

## Dependencies

- [ierc20](https://github.com/uniteum/ierc20) — `IERC20`.

## License

MIT License — Copyright (c) 2026 Uniteum
