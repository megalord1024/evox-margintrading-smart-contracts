// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol" as ERC20;
import "@openzeppelin/contracts/interfaces/IERC20.sol" as IERC20;
import "./libraries/REX_LIBRARY.sol";
import "hardhat/console.sol";

//  userId[totalHistoricalUsers] = msg.sender;
contract DepositVault is Ownable {
    constructor(address initialOwner, address dataHub) Ownable(initialOwner) {
        Datahub = IDataHub(dataHub);
    }

    IDataHub public Datahub;

    using REX_LIBRARY for uint256;

    uint256 public totalHistoricalUsers;

    uint256 public totalDepositors;

    mapping(address => bool) public userInitialized;
    mapping(uint256 => address) public userId;

    function fetchDecimals(address token) public view returns (uint256) {
        ERC20.ERC20 Token = ERC20.ERC20(token);
        return Token.decimals();
    }

    function fetchstatus(address user) external view returns (bool) {
        if (userInitialized[user] == true) {
            return true;
        } else {
            return false;
        }
    }

    /* DEPOSIT FUNCTION */
    /// @notice This deposits tokens and inits the user struct, and asset struct if new assets.
    /// @dev Explain to a developer any extra details
    /// @param token - the address of the token to be depositted
    /// @param amount - the amount of tokens to be depositted
    /// @return returns a bool to let the user know if deposit was successful.

    function deposit_token(
        address token,
        uint256 amount
    ) external returns (bool) {
        require(
            Datahub.FetchAssetInitilizationStatus(token) == true,
            "this asset is not available to be depositted or traded"
        );
        IERC20.IERC20 ERC20Token = IERC20.IERC20(token);
        require(ERC20Token.transferFrom(msg.sender, address(this), amount));

        Datahub.settotalAssetSupply(token, amount, true);
        Datahub.updateInterestIndex(
            token,
            REX_LIBRARY.calculateInterestRate(0,Datahub.returnAssetLogs(token))
        );

        (, uint256 liabilities, uint256 mmr, , , ) = Datahub.ReadUserData(
            msg.sender,
            token
        );
        // checks to see if user is in the sytem and inits their struct if not
        if (liabilities > 0) {
            // checks to see if the user has liabilities of that asset

            if (amount <= liabilities) {
                // if the amount is less or equal to their current liabilities -> lower their liabilities using the multiplier

                uint256 liabilityMultiplier = REX_LIBRARY
                    .calculatedepositLiabilityRatio(liabilities, amount);

                Datahub.alterLiabilities(
                    msg.sender,
                    token,
                    ((10 ** 18) - liabilityMultiplier)
                );

                Datahub.alterMMR(msg.sender, token, ((10 ** 18) - liabilityMultiplier));
            } else {
                // if amount depositted is bigger that liability info 0 it out
                uint256 amountAddedtoAssets = amount - liabilities; // amount - outstanding liabilities

                Datahub.addAssets(msg.sender, token, amountAddedtoAssets); // add to assets

                Datahub.removeLiabilities(msg.sender, token, liabilities); // remove all liabilities

                Datahub.removeMaintenanceMarginRequirement(
                    msg.sender,
                    token,
                    mmr
                ); // remove all mmr

               Datahub.changeMarginStatus(msg.sender);
            }
        } else {
            address[] memory users = new address[](1);
            users[0] = msg.sender;

            Datahub.checkIfAssetIsPresent(users, token);
            Datahub.addAssets(msg.sender, token, amount);
        }

        console.log("DEPOSIT COMPLETE");

        return true;
    }

    /* WITHDRAW FUNCTION */

    /// @notice This withdraws tokens from the exchange
    /// @dev Explain to a developer any extra details
    /// @param token - the address of the token to be withdrawn
    /// @param amount - the amount of tokens to be withdrawn
    /// @return returns a bool to let the user know if withdraw was successful.

    // IMPORTANT MAKE SURE USERS CAN'T WITHDRAW PAST THE LIMIT SET FOR AMOUNT OF FUNDS BORROWED
    function withdraw_token(
        address token,
        uint256 amount
    ) external returns (bool) {
        (uint256 assets, , ,uint256 pending , , ) = Datahub.ReadUserData(msg.sender, token);

        require(pending == 0);
        require(amount <= assets);

        IDataHub.AssetData memory assetInformation = Datahub.returnAssetLogs(
            token
        );

        uint256 AssetPriceCalulation = (assetInformation.assetPrice * amount) /
            10 ** 18; // this is 10*18 dnominated price of asset amount

        uint256 usersAMMR = Datahub.calculateAMMRForUser(msg.sender);

        uint256 usersTPV = Datahub.calculateTotalPortfolioValue(msg.sender);

        bool UnableToWithdraw = usersAMMR + AssetPriceCalulation > usersTPV;
        // if the users AMMR + price of the withdraw is bigger than their TPV dont let them withdraw this 

        require(!UnableToWithdraw);

        if (amount == assets) {
            // remove asset token from their portfolio
            Datahub.removeAssetToken(msg.sender);
            Datahub.removeAssets(msg.sender, token, amount);
        } else {
            Datahub.removeAssets(msg.sender, token, amount);
        }

        IERC20.IERC20 ERC20Token = IERC20.IERC20(token);
        ERC20Token.transfer(msg.sender, amount);

        Datahub.settotalAssetSupply(token, amount, false);

        IDataHub.AssetData memory assetLogs = Datahub.returnAssetLogs(token);

        // recalculate interest rate because total asset supply is changing 
        if (assetLogs.totalBorrowedAmount > 0) {
            Datahub.updateInterestIndex(
                token,
                REX_LIBRARY.calculateInterestRate(0,assetLogs)
            );
        }
        return true;
    }

    function alterdataHub(address _datahub) public onlyOwner {
        Datahub = IDataHub(_datahub);
    }

    function GetTokenDepositInfo(
        address token,
        address user
    ) public view returns (uint256[3] memory) {
        (uint256 assets, uint256 liabilities, , uint256 pending, , ) = Datahub
            .ReadUserData(user, token);
        return [assets, liabilities, pending];
    }

    receive() external payable {}
}
