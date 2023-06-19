module tagion.wallet.Basic;

import tagion.crypto.SecureInterfaceNet : HashNet;
import tagion.basic.Types : Buffer;

/**
     * Calculates the check-sum hash
     * Params:
     *   value = value to be checked
     *   salt = optional salt value
     * Returns: the double hash
     */
@safe
Buffer saltHash(const HashNet net, scope const(ubyte[]) value, scope const(ubyte[]) salt = null) {
    return net.rawCalcHash(net.rawCalcHash(value) ~ salt);
}
