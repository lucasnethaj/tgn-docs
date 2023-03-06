/// \file HashChainBlock.d
module tagion.hashchain.HashChainBlock;

import std.range : empty;
import tagion.crypto.Types : Fingerprint;
import tagion.hibon.HiBON : HiBON;

/** @brief File contains interface for HashChainBlock
 */

/**
 * \interface HashChainBlock
 * Interface represents block from hash chain
 */
@safe interface HashChainBlock {
    /** Returns hash of block
     *      \return hash
     */
    Fingerprint getHash() const;

    /** Returns fingerprint of previous block in chain
     *      \return fingerprint of previous block
     */
    Fingerprint getPrevious() const;

    /** Converts structure to HiBON
     *      \return HiBON copy of this structure
     */
    @trusted inout(HiBON) toHiBON() inout;

    /** Function that says whether this block has no predecessors
     *      \return true if this block is root block
     */
    final bool isRoot() const {
        return getPrevious.empty;
    }
}
