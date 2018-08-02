pragma solidity ^0.4.23;

/**
 *  @title MultiSigWallet Contract
 *
 *  @notice Implement operations which require multiple owner confirmations. It is inherited by TokenHolder.sol
 *
 */
// TODO change all uint => uint256
// TODO if else spacing handling
// TODO grouping public, internal, private functions
// TODO Period after comment
// A space after returns
contract MultiSigWallet {

    /** Events */

    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event WalletAddition(address indexed wallet);
    event WalletRemoval(address indexed wallet);
    event RequirementChange(uint16 required);
    event Propose(address sender,bytes32 transactionId);

    /**  Storage */
    // TODO variables ordering
    mapping(bytes32 => mapping(address => bool)) public confirmations;
    mapping(address => bool) public isWallet;
    address[] public wallets;
    uint16 public required;

    /**
        isExecuted mapping allows to check if a transaction (by hash) was already proposed and executed.
        Values could be :-
        00 :- initial state/Not proposed.
        01 :- Proposed state.
        11 :- Successfully executed state.
     */
    mapping(bytes32 => uint8) public isExecuted;

    /** Modifiers */

    modifier walletDoesNotExist(address wallet) {
        require(!isWallet[wallet], "Wallet address doesnt exist");
        _;
    }

    modifier walletExists(address wallet) {
        require(isWallet[wallet], "Wallet should be added to proceed for this transaction");
        _;
    }

    modifier confirmed(
        uint transactionId,
        address wallet) {

        require(confirmations[transactionId][wallet], "Transaction is not confirmed by this wallet");
        _;
    }

    modifier notConfirmed(
        uint transactionId,
        address wallet) {

        require(!confirmations[transactionId][wallet]);
        _;
     }

    modifier notExecuted(bytes32 transactionId) {

        require(!isExecuted[transactionId]);
        _;
    }

    modifier notNull(address _address) {
        require(_address != 0, "Wallet address should not be null");
        _;
    }

    modifier validRequirement(
        uint walletCount,
        uint16 _required) {

        require(_required <= walletCount
                && _required != 0
                && walletCount != 0,
                "Requirement to be set is incorrect");
        _;
    }

    /** @dev Contract constructor sets initial wallets and required number of confirmations.
      *
      * @param _wallets List of initial wallets.
      * @param _required Number of required confirmations.
      */
    constructor(
        address[] _wallets,
        uint16 _required)
        public
        validRequirement(_wallets.length, _required)
    {
        require(_wallets.length > 0,"Wallets cannot be empty");
        require(_required > 0,"Atleast one confirmation is required");
        require(_required <= _wallets,"Number of confirmations cannot be less than wallets");

        for (uint i = 0; i < _wallets.length; i++) {
            require(!isWallet[_wallets[i]] && _wallets[i] != 0, "Wallet address is incorrect or duplicate");
            isWallet[_wallets[i]] = true;
        }

        wallets = _wallets;
        required = _required;
    }

    /** Public functions */

    /** @dev Allows to propose a new wallet or confirm an already proposed wallet.
      *
      * @param _wallet Address of wallet which is to be proposed or confirmed.
      * @param proposeOrConfirm If true then transaction will be proposed otherwise confirmation is being done.
      *
      * @return transactionId   It is unique for each request.
      */
    function proposeOrConfirmAddWallet(
        address _wallet,
        bool proposeOrConfirm)
        notNull(wallet)
        validRequirement(wallets.length + 1, required)
        public
        returns (bytes32 transactionId)
    {
        transactionId = keccak256(abi.encodePacked(_wallet, this, "addWallet"));
        if(proposeOrConfirm) {
            require(isAlreadyProposedTransaction(transactionId) == false, "Transaction is already proposed!");
            require(isWallet[wallet] == false, "Wallet address already exists");
            performProposeTransaction(transactionId);
        }
        else {
            genericConfirmTransaction(transactionId);
            if (isExecuted[transactionId] == 11) {
                isWallet[wallet] = true;
                wallets.push(wallet);
                emit WalletAddition(wallet);
            }
        }
        return transactionId;
    }

    /** @dev Allows to propose removal of an wallet or confirm already proposed removal. Transaction has to be sent by wallet.
      *
      * @param wallet Address of wallet.
      * @param proposeOrConfirm If true then transaction will be proposed otherwise confirmation is being done.
      *
      * @return transactionId   It is unique for each request.
      */
    function proposeOrConfirmRemoveWallet(
        address _wallet,
        bool proposeOrConfirm)
        walletExists(wallet)
        public
        returns (bytes32 transactionId)
    {

        transactionId = keccak256(abi.encodePacked(_wallet, this, "removeWallet"));
        if(proposeOrConfirm) {
            require(isAlreadyProposedTransaction(transactionId) == false, "Transaction is already proposed!");
            performProposeTransaction(transactionId);
        }
        else {
            performConfirmTransaction(transactionId);
            if(isExecuted[transactionId] == 11) {
                isWallet[wallet] = false;
                for (uint i = 0; i < wallets.length - 1; i++)
                    if (wallets[i] == wallet) {
                        wallets[i] = wallets[wallets.length - 1];
                        break;
                    }
                wallets.length -= 1;
                if (required > wallets.length)
                    changeRequirement(wallets.length);
                emit WalletRemoval(wallet);
            }
        }
        return transactionId;
    }


    /** @dev Allows to propose or confirmation intent to replace an wallet with a new wallet. Transaction has to be sent by wallet.
      *
      * @param wallet Address of wallet to be replaced.
      * @param newWallet Address of new wallet.
      * @param proposeOrConfirm If true then transaction will be proposed otherwise confirmation is being done.
      *
      * @return transactionId   It is unique for each request.
      */
    function proposeOrConfirmReplaceWallet(
        address _oldWallet,
        address _newWallet,
        bool proposeOrConfirm)
        public
        walletExists(_oldWallet)
        walletDoesNotExist(_newWallet)
        returns(bytes32 transactionId)
    {
        transactionId = keccak256(abi.encodePacked(_oldWallet,_newWallet,this, "replaceWallet"));
        if(proposeOrConfirm) {
            require(isAlreadyProposedTransaction(transactionId) == false, "Transaction is already proposed!");
            performProposeTransaction(transactionId);
        }
        else {
            performConfirmTransaction(transactionId);
            if(isExecuted[transactionId] == 11 ){
                for (uint i = 0; i < wallets.length; i++)
                if (wallets[i] == wallet) {
                    wallets[i] = newWallet;
                    break;
                }
            isWallet[wallet] = false;
            isWallet[newWallet] = true;
            emit WalletRemoval(wallet);
            emit WalletAddition(newWallet);
            }
        }
        return transactionId;
     }

    /** @dev Allows to propose or confirm intent for changing for the number of required confirmations. Transaction has to be sent by wallet.
      *
      * @param _required Number of required confirmations.
      * @param proposeOrConfirm If true then transaction will be proposed otherwise confirmation is being done.
      *
      * @return transactionId   It is unique for each unique request.
      */
    function proposeOrConfirmChangeRequirement(
        uint16 _required,
        bool proposeOrConfirm)
        public
        validRequirement(wallets.length, _required)
        returns(bytes32 transactionId)
    {
        transactionId = keccak256(abi.encodePacked(_required, _newWallet, this, "changeRequirement"));
        if(proposeOrConfirm) {
            require(isAlreadyProposedTransaction(transactionId) == false, "Transaction is already proposed!");
            performProposeTransaction(transactionId);
        }
        else {
            performConfirmTransaction(transactionId);
            if(isExecuted[transactionId] == 11) {
                required = _required;
                emit RequirementChange(_required);
            }
        }
    }

    /** @dev Allows to propose or confirm intent for wallet to be revoked for a transaction.
      *
      * @param transactionId Transaction ID.
      * @param proposeOrConfirm If true then transaction will be proposed otherwise confirmation is being done.
      *
      * @return transactionId   It is unique for each unique request.
      */
    function proposeOrConfirmRevokeConfirmation(
        bytes32 transactionId,
        bool proposeOrConfirm)
        public
        walletExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
        returns(bytes32 transactionId)
    {
        if(proposeOrConfirm) {
            require(isAlreadyProposedTransaction(transactionId) == false, "Transaction is already proposed!");
            performProposeTransaction(transactionId);
        }
        else {
            performConfirmTransaction(transactionId);
            if(isExecuted[transactionId] == 11){
                confirmations[transactionId][msg.sender] = false;
                emit Revocation(msg.sender, transactionId);
            }
        }
        return transactionId;
    }

    /** Internal functions */

    /**  @dev It is called whereever we need to propose transactions in multisig.
      *
      *  @param transactionId It marks it in proposed state against the wallet which has sent the transaction.
      *
      */
    function performProposeTransaction(
        bytes32 transactionId)
        internal
    {
        isExecuted[transactionId] = 01;
        confirmations[transactionId][msg.sender] = true;

        emit Propose(msg.sender, transactionId);
    }

    /**  @dev It is used to send the transaction to confirmation state by the wallet who has sent the transaction.
      *
      *  @param transactionId It marks this transaction id as confirmed against the wallet which has sent the transaction.
      */
    function performConfirmTransaction(
        bytes32 transactionId)
        internal
        walletExists(msg.sender)
        notConfirmed(transactionId, msg.sender) //transactionExists(transactionId) check whether this is needed
    {
        require(isExecuted[transactionId] == 00, "Please first propose the transaction");
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId); // TODO Remove
        if ((isExecuted[transactionId] == 01)) {//transaction is not executed,only proposed
            if (isConfirmed(transactionId)) {
                isExecuted[transactionId] = 11;
            }

        }

    }

    /** @dev  It is used to check whether the transaction is in proposed state.
      *
      * @param transactionId It denotes whose transaction status(Proposed state) is to be checked.
      *
      * @bool  If true then transaction is in proposed state.
      */
    function isAlreadyProposedTransaction(
        bytes32 transactionId)
        internal
        returns (bool /* success */)
    {
        return isExecuted[transactionId] == 01;
    }

    // TODO Do we need below functions
//    /** @dev Returns the confirmation status of a transaction.
//      *
//      * @param transactionId Transaction ID.
//      *
//      * @return Confirmation status.
//      */
//    function isConfirmed(bytes32 transactionId)
//        public
//        constant
//        returns (bool)
//    {
//        uint count = 0;
//        for (uint i = 0; i < wallets.length; i++) {
//            if (confirmations[transactionId][wallets[i]])
//                count += 1;
//            if (count == required)
//                return true;
//        }
//    }
//
//    /**
//      *  @dev Returns number of confirmations of a transaction.
//      *
//      *  @param transactionId Transaction ID.
//      *
//      *  @return Number of confirmations.
//      */
//    function getConfirmationCount(
//        bytes32 transactionId)
//        public
//        constant
//        returns (uint count)
//    {
//        for (uint i = 0; i < wallets.length; i++)
//            if (confirmations[transactionId][wallets[i]])
//                count += 1;
//    }
//
//
//
//    /**  @dev Returns array with wallet addresses, which confirmed transaction.
//      *
//      *  @param transactionId Transaction ID.
//      *
//      *  @return Returns array of wallet addresses.
//      */
//    function getConfirmations(
//        bytes32 transactionId)
//        public
//        constant
//        returns (address[] _confirmations)
//    {
//        address[] memory confirmationsTemp = new address[](wallets.length);
//        uint count = 0;
//        uint i;
//        for (i = 0; i < wallets.length; i++)
//            if (confirmations[transactionId][wallets[i]]) {
//                confirmationsTemp[count] = wallets[i];
//                count += 1;
//            }
//        _confirmations = new address[](count);
//        for (i = 0; i < count; i++)
//            _confirmations[i] = confirmationsTemp[i];
//    }

}