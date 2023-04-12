/** 
* Key-pair recovery generator
*/
module tagion.wallet.KeyRecover;

import tagion.crypto.SecureInterfaceNet : HashNet;
import tagion.crypto.SecureNet : scramble;
import tagion.utils.Miscellaneous : xor;
import tagion.basic.Types : Buffer;
import tagion.basic.Message;

import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBONRecord;

import std.exception : assumeUnique;
import std.string : representation;
import std.range : lockstep, StoppingPolicy, indexed, iota;
import std.algorithm.mutation : copy;
import std.algorithm.iteration : map, filter;
import std.array : array;

import tagion.wallet.WalletRecords : RecoverGenerator;
import tagion.wallet.WalletException : KeyRecoverException;
import tagion.basic.tagionexceptions : Check;

alias check = Check!KeyRecoverException;

/**
 * Key-pair recovery generator
 */
@safe
struct KeyRecover {
    enum MAX_QUESTION = 10;
    enum MAX_SEEDS = 64;
    const HashNet net;
    protected RecoverGenerator generator;

    /**
     * 
     * Params:
     *   net = hash used by the recovery
     */
    @nogc
    this(const HashNet net) pure nothrow {
        this.net = net;
    }

    /**
     * 
     * Params:
     *   net = hash used by the recovery 
     *   doc = document of the recovery generator 

     */
    this(const HashNet net, Document doc) {
        this.net = net;
        generator = RecoverGenerator(doc);
    }

    /**
     * 
     * Params:
     *   net = hash used by the recovery
     *   generator = the recover generator  
     */
    this(const HashNet net, RecoverGenerator generator) {
        this.net = net;
        this.generator = generator;
    }

    /**
     * 
     * Returns: the document of the generator
     */
    const(Document) toDoc() const {
        return generator.toDoc;
    }

    /**
     * Generates the quiz hash of the from a list of questions and answers
     * 
     * Params:
     *   questions = List of questions 
     *   answers = List for answers
     * Returns: List of common hashs of question and answers
     */
    Buffer[] quiz(scope const(string[]) questions, scope const(char[][]) answers) const @trusted
    in {
        assert(questions.length is answers.length);
    }
    do {
        auto results = new Buffer[questions.length];
        foreach (ref result, question, answer; lockstep(results, questions, answers, StoppingPolicy
                .requireSameLength)) {
            scope strip_down = cast(ubyte[]) answer.strip_down;
            scope answer_hash = net.rawCalcHash(strip_down);
            scope question_hash = net.rawCalcHash(question.representation);
            // scope (exit) {
            //     strip_down.sceamble;
            //     answer_hash.scramble;
            //     question_hash.scramble;
            // }
            //            const hash = net.rawCalcHash(answer);
            result = net.rawCalcHash(answer_hash ~ question_hash);
        }
        return results;
    }

    /**
     * Total number of combination of possible seed value
     * Params:
     *   M = number of question 
     *   N = confidence
     * Returns: totol number of combinations
     */
    @nogc
    static uint numberOfSeeds(const uint M, const uint N) pure nothrow
    in {
        assert(M >= N);
        assert(M <= 10);
    }
    do {
        return (M - N) * N + 1;
    }

    @nogc
    static unittest {
        assert(numberOfSeeds(10, 5) is 26);
    }

    /**
     * Calculates the check-sum hash
     * Params:
     *   value = value to be checked
     *   salt = optional salt value
     * Returns: the double hash
     */
    Buffer checkHash(scope const(ubyte[]) value, scope const(ubyte[]) salt = null) const {
        return net.rawCalcHash(net.rawCalcHash(value) ~ salt);
    }

    static void iterateSeeds(
            const uint M,
            const uint N,
            scope void delegate(scope const(uint[]) indices) @safe dg) {
        scope include = new uint[N];
        iota(N).copy(include);
        void local_search(const int index, const int size) @safe {
            if (index >= 0) {
                dg(include);
                pragma(msg, "review(cbr): Side channel attack fixed");
                if (include[index] < size) {
                    include[index]++;
                    local_search(index, size);
                }
            else if (index > 0) {
                    include[index - 1]++;
                    local_search(index - 1, size - 1);
                }
            }
        }

        local_search(cast(int) include.length - 1, M - 1);
    }

    /**
     * Creates the key-pair
     * Params:
     *   questions = List of question 
     *   answers = List of answers
     *   confidence = Confidence of the answers
     *   seed = optional seed value of the key-pair
     */
    void createKey(
            scope const(string[]) questions,
    scope const(char[][]) answers,
    const uint confidence,
    scope const(ubyte[]) seed = null) {
        createKey(quiz(questions, answers), confidence, seed);
    }

    /**
     * Ditto except is uses a list of hashes
     * This can be used of something else than quiz is used
     * Params:
     *   A = List of hashes
     *   confidence = confidence
     *   seed = option
     */
    void createKey(
            Buffer[] A,
            const uint confidence,
            scope const(ubyte[]) seed)
    in (seed.length <= net.hashSize)
    do {
        scope R = new ubyte[net.hashSize];
        scramble(R);
        scope (exit) {
            scramble(R);
        }
        quizSeed(R, A, confidence);
    }

    /**
     * Generates the quiz seed values from the privat key R and the quiz list
     * 
     * Params:
     *   R = generated private-key
     *   A = List of hashes
     *   confidence = number of minimum correct answern
     */
    void quizSeed(scope ref const(ubyte[]) R,
    scope Buffer[] A,
    const uint confidence) {
        scope (success) {
            generator.confidence = confidence;
            generator.S = checkHash(R);
        }
        scope (failure) {
            generator.Y = null;
            generator.S = null;
            generator.confidence = 0;
        }
        check(A.length > 1, message("Number of questions must be more than one"));
        check(confidence <= A.length, message(
                "Number qustions must be lower than or equal to the confidence level (M=%d and N=%d)",
                A.length, confidence));
        check(A.length <= MAX_QUESTION, message("Mumber of question is %d but it should not exceed %d",
                A.length, MAX_QUESTION));
        const number_of_questions = cast(uint) A.length;
        const seeds = numberOfSeeds(number_of_questions, confidence);
        check(seeds <= MAX_SEEDS, message("Number quiz-seeds is %d which exceed that max value of %d",
                seeds, MAX_SEEDS));
        generator.Y = new Buffer[seeds];
        uint count;
        void calculate_this_seeds(scope const(uint[]) indices) @safe {
            scope list_of_selected_answers_and_the_secret = indexed(A, indices);
            pragma(msg, "review(cbr): Recovery now used Y_a = R x H(A_a) instead of Y_a = R x H(A_a)");

            generator.Y[count] = xor(R, net.rawCalcHash(
                    xor(list_of_selected_answers_and_the_secret)));
            count++;
            //            return false;
        }

        iterateSeeds(number_of_questions, confidence, &calculate_this_seeds);
    }

    /**
     * Generate the private-key from quiz (correct answers)
     * Params:
     *   R = generated private-key
     *   questions = list of questions
     *   answers = list of answers
     * Returns: true if it was successfully
     */
    bool findSecret(
            scope ref ubyte[] R,
            scope const(string[]) questions,
    scope const(char[][]) answers) const {
        return findSecret(R, quiz(questions, answers));
    }

    /** 
     * Recover the private-key from the hash-list A
     * The hash-list is usually the question+answers hash 
     * Params:
     *   R = Private-key
     *   A = List of hashes 
     * Returns: true if it was successfully
     */
    bool findSecret(scope ref ubyte[] R, Buffer[] A) const {
        check(A.length > 1, message("Number of questions must be more than one"));
        check(generator.confidence <= A.length,
                message("Number qustions must be lower than or equal to the confidence level (M=%d and N=%d)",
                A.length, generator.confidence));
        const number_of_questions = cast(uint) A.length;
        const seeds = numberOfSeeds(number_of_questions, generator.confidence);

        bool result;
        void search_for_the_secret(scope const(uint[]) indices) @safe {
            scope list_of_selected_answers_and_the_secret = indexed(A, indices);
            pragma(msg, "review(cbr): Recovery now used Y_a = R x H(A_a) instead of Y_a = R x H(A_a)");
            const guess = net.rawCalcHash(xor(list_of_selected_answers_and_the_secret));
            scope _R = new ubyte[net.hashSize];
            foreach (y; generator.Y) {
                xor(_R, y, guess);
                pragma(msg, "review(cbr): constant time on a equal - sidechannel attack");
                if (generator.S == checkHash(_R)) {
                    _R.copy(R);
                    result = true;
                }
            }
        }

        pragma(msg, "review(cbr): Constant time - sidechannel attack");
        iterateSeeds(number_of_questions, generator.confidence, &search_for_the_secret);
        return result;
    }
}

/**
 * Strip down question and answer
 * Converts the string to lower-case and takes only letters and numbers
 * Params:
 *   text = 
 * Returns: stripped text
 */
char[] strip_down(const(char[]) text) pure @safe
out (result) {
    assert(result.length > 0);
}
do {
    import std.ascii : toLower, isAlphaNum;

    return text
        .map!(c => cast(char) toLower(c))
        .filter!(c => isAlphaNum(c))
        .array;
}

static immutable(string[]) standard_questions;

shared static this() {
    standard_questions = [
        "What is your favorite book?",
        "What is the name of the road you grew up on?",
        "What is your mother’s maiden name?",
        "What was the name of your first/current/favorite pet?",
        "What was the first company that you worked for?",
        "Where did you meet your spouse?",
        "Where did you go to high school/college?",
        "What is your favorite food?",
        "What city were you born in?",
        "Where is your favorite place to vacation?"
    ];
}

///
unittest {
    import tagion.crypto.SecureNet : StdHashNet;
    import std.array : join;

    auto selected_questions = indexed(standard_questions, [0, 2, 3, 7, 8]).array.idup;
    string[] answers = [
        "mobidick",
        "Mother Teresa!",
        "Pluto",
        "Pizza",
        "Maputo"
    ];
    const net = new StdHashNet;
    auto recover = KeyRecover(net);
    recover.createKey(selected_questions, answers, 3, null);

    auto R = new ubyte[net.hashSize];

    { // All the ansers are correct
        const result = recover.findSecret(R, selected_questions, answers);
        assert(R.length == net.hashSize);
        assert(result); // Password found
    }

    { // 3 out of 5 answers are correct. This is a valid answer to generate the secret key
        string[] good_answers = [
            "MobiDick",
            "MOTHER TERESA",
            "Fido",
            "pizza",
            "Maputo"
        ];
        auto goodR = new ubyte[net.hashSize];
        const result = recover.findSecret(goodR, selected_questions, good_answers);
        assert(R.length == net.hashSize);
        assert(result); // Password found
        assert(R == goodR);
    }

    { // 2 out of 5 answers are correct. This is NOT a valid answer to generate the secret key
        string[] bad_answers = [
            "mobidick",
            "Monalisa",
            "Fido",
            "Burger",
            "Maputo"
        ];
        auto badR = new ubyte[net.hashSize];
        const result = recover.findSecret(badR, selected_questions, bad_answers);
        assert(!result); // Password not found
        assert(R != badR);

    }
}
