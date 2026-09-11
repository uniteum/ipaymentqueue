// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "ierc20/IERC20.sol";

/**
 * @title IPaymentQueue
 * @notice Pays each payment id at most once, from a float of one ERC-20 token that anyone can top
 * up. A payment the float cannot cover waits in line until it can; a payment the token refuses is
 * recorded as failed and does not hold up the ones behind it.
 * @dev Each queue is made by {make}, one per owner, token and variant, and belongs to whoever made
 * it. The factory surface underneath ({proto}, the bytes forms of {make} and {made}, {zzInit}) comes
 * from {IPrototype}.
 *
 * The caller chooses the id, and it is the idempotency key: the first {pay} for an id fixes its
 * recipient and amount, and every later {pay} for it is a no-op.
 * @author Paul Reinholdtsen (reinholdtsen.eth)
 */
interface IPaymentQueue {
    /**
     * @notice Where a payment id stands in this queue.
     * @dev `Unknown`: never submitted. `Queued`: waiting for float. `Paid`: transferred. `Failed`: the
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
     * float. Fixed for the life of the queue.
     */
    function owner() external view returns (address);

    /**
     * @notice The token this queue pays in.
     */
    function token() external view returns (IERC20);

    /**
     * @notice Where payment `id` stands.
     */
    function statusOf(uint256 id) external view returns (Status);

    /**
     * @notice How many payments are waiting for float.
     */
    function queued() external view returns (uint256);

    /**
     * @notice Pay `amount` to `recipient` under `id`, at most once.
     * @dev Only the {owner}. A no-op if `id` is already known. Otherwise pays at once when nothing is
     * waiting and the float covers `amount`, and joins the back of the line when not, so a new payment
     * never passes one already waiting. A transfer the token refuses, by reverting or by returning
     * false, marks the id `Failed` rather than reverting the call.
     * @param id Idempotency key chosen by the caller.
     * @param recipient Address to pay.
     * @param amount Amount in the token's base units.
     * @return status The status of `id` after the call, so simulating it previews the outcome.
     */
    function pay(uint256 id, address recipient, uint256 amount) external returns (Status status);

    /**
     * @notice Pay waiting payments, oldest first, while the float covers the next one.
     * @dev Anyone may call. Stops at the first payment the float cannot cover and leaves it waiting.
     * A payment the token refuses is marked `Failed` and passed over. Simulate the call to learn
     * whether a sweep would settle anything before paying gas for one.
     * @param limit The most payments to settle in this call.
     * @return settled How many payments left the line, paid or failed.
     */
    function processPayments(uint256 limit) external returns (uint256 settled);

    /**
     * @notice Send `amount` of the float to `to`.
     * @dev Only the {owner}. Reverts if the transfer fails. Withdrawing float that waiting payments
     * need delays them; it does not cancel them.
     */
    function withdraw(address to, uint256 amount) external;

    /**
     * @notice Predict the queue {make} would return for `owner` and `token`, without making it.
     * @param owner The account that would call {make}, and so own the queue.
     * @param token The token the queue would pay in.
     * @param variant Vanity-mining input; 0 for the canonical address.
     * @return exists Whether that queue has already been made.
     * @return home The queue's deterministic address.
     * @return salt The CREATE2 salt derived from the arguments and `variant`.
     */
    function made(address owner, IERC20 token, uint256 variant)
        external
        view
        returns (bool exists, address home, bytes32 salt);

    /**
     * @notice Make a queue that pays in `token`, owned by the caller, or return the one already made.
     * @dev Callable on the prototype or on any queue; either way the caller becomes the owner.
     * @param token The token the queue pays in.
     * @param variant Vanity-mining input; 0 for the canonical address.
     * @return queue The caller's queue for `token` and `variant`.
     */
    function make(IERC20 token, uint256 variant) external returns (IPaymentQueue queue);

    /**
     * @notice ABI-encode a queue's init args, as {make} passes them to {zzInit}.
     */
    function encode(address owner, IERC20 token) external pure returns (bytes memory args);

    /**
     * @notice Emitted when payment `id` joins the line to wait for float.
     */
    event PaymentQueued(uint256 indexed id, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when payment `id` is transferred, by {pay} or by {processPayments}.
     */
    event PaymentPaid(uint256 indexed id, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when the token refuses the transfer for payment `id`.
     */
    event PaymentFailed(uint256 indexed id, address indexed recipient, uint256 amount);

    /**
     * @notice The transfer for payment `id` ran out of gas, which says nothing about whether the
     * token would accept it. Nothing is recorded; send the call again with more gas.
     */
    error TransferOutOfGas(uint256 id);
}
