// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module casuino::chipsui {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui_system::staking_pool::{Self, StakedSui};
    use std::vector;
    use std::option;

    struct Exchange has key {
        id: UID,
        treasury_cap: TreasuryCap<CHIPSUI>,
        liquid_pools: vector<LiquidPool>,
    }

    struct LiquidPool has key, store {
        id: UID,
        owner: address,
        staked_sui: StakedSui,
        amount: u64,
        expired: u64,
    }

    struct CHIPSUI has drop {}

    fun init(witness: CHIPSUI, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<CHIPSUI>(witness, 2, b"CHIPSUI", b"CHIPSUI", b"CHIPSUI", option::none(), ctx);
        transfer::public_freeze_object(metadata);
        transfer::share_object(Exchange {
            id: object::new(ctx),
            treasury_cap: treasury_cap,
            liquid_pools:vector::empty<LiquidPool>(),
        });
    }

    public entry fun depositStakedSui(exchange: &mut Exchange, staked_sui: StakedSui, ctx: &mut TxContext) {
        let principal_amount = staking_pool::staked_sui_amount(&staked_sui);
        let sender = tx_context::sender(ctx);
        let newLS = LiquidPool {
            id: object::new(ctx),
            owner: sender,
            staked_sui: staked_sui,
            amount: principal_amount,
            expired: 0,
        };
        vector::push_back(&mut exchange.liquid_pools, newLS);
        coin::mint_and_transfer(&mut exchange.treasury_cap, principal_amount, sender, ctx);
    }

    public entry fun withdrawStakedSui(exchange: &mut Exchange, coin: Coin<CHIPSUI>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let index = index_of_ls(&exchange.liquid_pools, coin::value(&coin), sender);
        if (index == vector::length(&exchange.liquid_pools)) {
            transfer::public_transfer(coin, sender);
        } else {
            let LiquidPool { id, owner, staked_sui, amount, expired } = vector::remove(&mut exchange.liquid_pools, index);
            // If the input value is larger than amount here, it would be good to add logic to take it some times and return some of it.
            transfer::public_transfer(staked_sui, owner);
            coin::burn(&mut exchange.treasury_cap, coin);
            object::delete(id);
        }
    }

    fun index_of_ls(ls: &vector<LiquidPool>, amount: u64, sender: address): u64 {
        let i = 0;
        let l = vector::length(ls);
        while (i < l) {
            let ls = vector::borrow(ls, i);
            if (ls.amount == amount && sender == ls.owner) {
                return i
            };
            i = i + 1;
       };
       return l
    }
}