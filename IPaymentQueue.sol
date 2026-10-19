// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "ierc20/IERC20.sol";

/**
 * @title IPaymentQueue
 * @notice Pays each payment id at most once, from funds in one ERC-20 token that anyone can top
 * up, keeping back a fee from each payment for the owner. A payment the funds cannot cover waits in
 * line until it can; a payment the token refuses is recorded as failed and does not hold up the ones
 * behind it.
 * @dev Each queue is made by {make}, one per owner, token and variant, and belongs to whoever made
 * it. The factory surface underneath ({proto}, the bytes forms of {make} and {made}, {zzInit}) comes
 * from {IPrototype}.
 *
 * The caller chooses the id, and it is the idempotency key: the first {pay} for an id fixes its
 * recipient, amount and fee, and every later {pay} for it is a no-op.
 *
 * The fee is named with each payment, in basis points of its amount, and is kept when the payment is
 * paid: the recipient gets the rest. Kept fees accrue apart from the funds, so they never pay anyone
 * and the owner withdraws them separately, with {withdrawFees}.
 * @author Paul Reinholdtsen (reinholdtsen.eth)
 */
interface IPaymentQueue {
    /**
     * @notice Where a payment id stands in this queue.
     * @dev `Unknown`: never submitted. `Queued`: waiting for funds. `Paid`: transferred. `Failed`: the
     * token refused the transfer; the id is spent and is never retried.
     */
    enum Status {
        Unknown,
        Queued,
        Paid,
        Failed
    }

    /**
     * @notice The account that made this queue, and the only one that may pay from it or withdraw its
     * funds or fees. Fixed for the life of the queue.
     */
    function owner() external view returns (address);

    /**
     * @notice The token this queue pays in: the one given to {make}, or the one its lookup resolved to
     * when the queue was made. Fixed for the life of the queue.
     */
    function token() external view returns (IERC20);

    /**
     * @notice Where payment `id` stands.
     */
    function statusOf(uint256 id) external view returns (Status);

    /**
     * @notice The block in which payment `id` reached its current status, or 0 while it is `Unknown`.
     * @dev The transaction that set the status emitted its event in that block, so filtering that one
     * block's logs on the indexed `id` finds it, however long ago it was.
     */
    function blockOf(uint256 id) external view returns (uint256);

    /**
     * @notice How many payments are waiting for funds.
     */
    function queued() external view returns (uint256);

    /**
     * @notice Fees kept from paid payments and not yet withdrawn.
     */
    function fees() external view returns (uint256);

    /**
     * @notice What the queue can pay out: the token it holds, less the accrued {fees}.
     * @dev A payment is paid only while its whole amount, fee included, is within this.
     */
    function funds() external view returns (uint256);

    /**
     * @notice Pay `amount` less its fee to `recipient` under `id`, at most once, and keep the fee.
     * @dev Only the {owner}. A no-op if `id` is already known. Otherwise pays at once when nothing is
     * waiting and the funds cover `amount`, and joins the back of the line when not, so a new payment
     * never passes one already waiting. A transfer the token refuses, by reverting or by returning
     * false, marks the id `Failed` rather than reverting the call, and keeps no fee.
     *
     * The fee is `amount * feeBasisPoints / 10_000`, rounded down. It accrues to {fees} when the payment
     * is paid; the recipient is transferred the rest.
     * @param id Idempotency key chosen by the caller.
     * @param recipient Address to pay.
     * @param amount Amount in the token's base units, fee included.
     * @param feeBasisPoints The share of `amount` to keep, in hundredths of a percent. Reverts with
     * {FeeTooHigh} above 10,000.
     * @return status The status of `id` after the call, so simulating it previews the outcome.
     */
    function pay(uint256 id, address recipient, uint256 amount, uint256 feeBasisPoints)
        external
        returns (Status status);

    /**
     * @notice Pay waiting payments, oldest first, while the funds cover the next one.
     * @dev Anyone may call. Stops at the first payment the funds cannot cover and leaves it waiting.
     * A payment the token refuses is marked `Failed` and passed over. Simulate the call to learn
     * whether a sweep would settle anything before paying gas for one.
     * @param limit The most payments to settle in this call.
     * @return settled How many payments left the line, paid or failed.
     */
    function processPayments(uint256 limit) external returns (uint256 settled);

    /**
     * @notice Send `amount` of the funds to `to`.
     * @dev Only the {owner}. Reverts with {InsufficientFunds} when `amount` exceeds {funds}, so accrued
     * fees are out of reach here, and reverts if the transfer fails. Withdrawing funds that waiting
     * payments need delays them; it does not cancel them.
     */
    function withdrawFunds(address to, uint256 amount) external;

    /**
     * @notice Send `amount` of the accrued fees to `to`.
     * @dev Only the {owner}. Reverts with {InsufficientFees} when `amount` exceeds {fees}, and reverts
     * if the transfer fails. Leaves the funds as they were.
     */
    function withdrawFees(address to, uint256 amount) external;

    /**
     * @notice Predict the queue {make} would return for `owner` and `token`, without making it.
     * @dev `token` is taken as given: nothing checks that it is deployed or resolves a lookup, so a
     * queue can be predicted on a chain its token or lookup has not reached yet.
     * @param owner The account that would call {make}, and so own the queue.
     * @param token The token the queue would pay in, or an {IAddressLookup} that resolves to it.
     * @param variant Vanity-mining input; 0 for the canonical address.
     * @return exists Whether that queue has already been made.
     * @return home The queue's deterministic address.
     * @return salt The CREATE2 salt derived from the arguments and `variant`.
     */
    function made(address owner, address token, uint256 variant)
        external
        view
        returns (bool exists, address home, bytes32 salt);

    /**
     * @notice Make a queue that pays in `token`, owned by the caller, or return the one already made.
     * @dev Callable on the prototype or on any queue; either way the caller becomes the owner.
     *
     * `token` may be the token itself or an {IAddressLookup} whose `value()` is the token on the
     * current chain. The queue's address is derived from `token` as given, so a queue keyed by a
     * lookup lands at the same address on every chain and pays in whatever the lookup resolves to
     * there. Reverts with {UnmappedLookup} when `token` has no code, or is a lookup that resolves to
     * `address(0)`.
     * @param token The token the queue pays in, or an {IAddressLookup} that resolves to it.
     * @param variant Vanity-mining input; 0 for the canonical address.
     * @return queue The caller's queue for `token` and `variant`.
     */
    function make(address token, uint256 variant) external returns (IPaymentQueue queue);

    /**
     * @notice ABI-encode a queue's init args, as {make} passes them to {zzInit}.
     */
    function encode(address owner, address token) external pure returns (bytes memory args);

    /**
     * @notice Emitted when payment `id` joins the line to wait for funds. `amount` includes `fee`,
     * which will be kept when it is paid.
     */
    event PaymentQueued(uint256 indexed id, address indexed recipient, uint256 amount, uint256 fee);

    /**
     * @notice Emitted when payment `id` is paid, by {pay} or by {processPayments}: `amount - fee` was
     * transferred to `recipient` and `fee` accrued.
     */
    event PaymentPaid(uint256 indexed id, address indexed recipient, uint256 amount, uint256 fee);

    /**
     * @notice Emitted when the token refuses the transfer for payment `id`. Nothing moved and no fee
     * was kept; `fee` is what would have been.
     */
    event PaymentFailed(uint256 indexed id, address indexed recipient, uint256 amount, uint256 fee);

    /**
     * @notice The transfer for payment `id` ran out of gas, which says nothing about whether the
     * token would accept it. Nothing is recorded; send the call again with more gas.
     */
    error TransferOutOfGas(uint256 id);

    /**
     * @notice `lookup`, given to {make} as the token, has no code on this chain, or is an
     * {IAddressLookup} that resolves to `address(0)`. No queue is made.
     */
    error UnmappedLookup(address lookup);

    /**
     * @notice `feeBasisPoints` exceeds 10,000, more than the whole amount. Nothing is recorded.
     */
    error FeeTooHigh(uint256 feeBasisPoints);

    /**
     * @notice A {withdrawFunds} asked for more than the funds; `available` is what {funds} returns.
     */
    error InsufficientFunds(uint256 available);

    /**
     * @notice A {withdrawFees} asked for more than has accrued; `available` is what {fees} holds.
     */
    error InsufficientFees(uint256 available);
}
