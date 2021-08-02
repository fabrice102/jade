{-# LANGUAGE MultiParamTypeClasses, AllowAmbiguousTypes, FlexibleContexts, FunctionalDependencies #-}
module VM where

import Prelude hiding (fail)
import Numeric (showHex)
import Mode
import ReadByte
import Data.Word (Word8)

class (ReadByte m, Num s) => (VM m s) | m -> s where
  fail :: String -> m a
  checkFinal :: m ()
  finish :: s -> m a
  putIntcblock :: [Integer] -> m ()
  intcblock :: Integer -> m s
  putBytecblock :: [[Word8]] -> m ()
  bytecblock :: Integer -> m s
  mode :: m Mode
  logicSigVersion :: m Integer
  push :: s -> m ()
  pop :: m s
  transaction :: Integer -> m s
  global :: Integer -> m s
  eq :: s -> s -> m s
  le :: s -> s -> m s
  isZero :: s -> m Bool
  jump :: Integer -> m ()
  groupTransaction :: Integer -> Integer -> m s
  groupTransactionArray :: Integer -> Integer -> Integer -> m s
  store :: Integer -> s -> m ()
  load :: Integer -> m s
  appGlobalGet :: s -> m s
  appGlobalPut :: s -> s -> m ()
  keccak256 :: s -> m s
  itob :: s -> m s
  btoi :: s -> m s
  
unused :: VM m s => Integer -> m a
unused oc = fail $ "use of unused opcode: 0x" ++ (showHex oc "")

stub :: VM m s => String -> m a
stub instr = fail $ "finish implementation for " ++ instr

continue :: VM m s => m ()
continue = return ()

logicSigVersionGE :: VM m s => Integer -> String -> m ()
logicSigVersionGE lsv part = do
  actualLsv <- logicSigVersion
  if lsv > actualLsv
    then fail $ "need LogicSigVersion >= " ++ (show lsv) ++ " for " ++ part ++ " but LogicSigVersion =" ++ (show actualLsv)
    else continue

inMode :: VM m s => Mode -> String -> m ()
inMode md part = do
  actualMd <- mode
  if actualMd /= md
    then fail $ "need mode " ++ (show md) ++ " for " ++ part ++ " but in mode " ++ (show actualMd)
    else continue

cost _ = return ()

{-

callsub offset = ThisVM $ \s -> Partial s 42
retsub = ThisVM $ \s -> Partial s 42

push x = ThisVM $ \s -> Partial s 42
pop = ThisVM $ \s -> Partial s 42

pop_uint64 = do
  x <- pop
  return x
-}

execute 0x00 = fail "err"
execute 0x01 = stub "sha256"
execute 0x02 = do -- keccak
  lsv <- logicSigVersion
  cost $ if lsv == 1 then 26 else 130
  (pop >>= keccak256) >>= push
  
execute 0x03 = stub "sha512_256"
execute 0x04 = stub "ed25519verify"
-- 0x05-0x07 unused
{-
execute 0x08 = do
  b <- pop_uint64
  a <- pop_uint64
  let c = a + b in
    if c >= 2 ^ 64 then
      fail "overflow +"
      else push c
execute 0x09 = do
  b <- pop_uint64
  a <- pop_uint64
  if b > a
    then fail "overflow -"
    else push $ a - b
execute 0x0a = do
  b <- pop_uint64
  a <- pop_uint64
  huh <- isZero b
  if huh
    then fail "divide by zero"
    else push $ a -- / b
execute 0x0b = stub "*"
-}
execute 0x0c = do
  b <- pop
  a <- pop
  le a b >>= push
-- the following are implemented as the Go VM
-- but we may need to treat each specially
-- for precision purposes
execute 0x0d = do -- >
  execute 0x4c -- swap
  execute 0x0c -- <
execute 0x0e = do -- <=
  execute 0x0d -- >
  execute 0x14 -- !
execute 0x0f = do -- >=
  execute 0x0c -- <
  execute 0x14 -- !
execute 0x10 = do -- &&
  b <- pop
  a <- pop
  huhb <- isZero b
  huha <- isZero a
  push $ if huha && huhb then 1 else 0
execute 0x11 = do -- ||
  b <- pop
  a <- pop
  huhb <- isZero b
  huha <- isZero a
  push $ if huha || huhb then 1 else 0
execute 0x12 = do -- ==
  b <- pop
  a <- pop
  eq a b >>= push
-- decomposing in this way shouldn't lose information for any lattice
-- which distinguishes 0
execute 0x13 = do -- !=
  execute 0x12 -- ==
  execute 0x14 -- !
execute 0x14 = do -- !
  a <- pop
  huh <- isZero a
  push $ if huh then 1 else 0
execute 0x15 = stub "len"
execute 0x16 = (pop >>= itob) >>= push -- itob
execute 0x17 = (pop >>= btoi) >>= push -- btoi
execute 0x18 = stub "%"
execute 0x19 = stub "|"
execute 0x1a = stub "&"
execute 0x1b = stub "^"
execute 0x1c = stub "~"
execute 0x1d = stub "mulw"
execute 0x1e = stub "addw"
execute 0x1f = stub "divmodw"
execute 0x20 = readIntcblock >>= putIntcblock -- intcblock
execute 0x21 = (readUint8 >>= intcblock) >>= push -- intc
execute 0x22 = (intcblock 0) >>= push -- intc_0
execute 0x23 = (intcblock 1) >>= push -- intc_1
execute 0x24 = (intcblock 2) >>= push -- intc_2
execute 0x25 = (intcblock 3) >>= push -- intc_3
execute 0x26 = readBytecblock >>= putBytecblock -- bytecblock
execute 0x27 = (readUint8 >>= bytecblock) >>= push -- bytec
execute 0x28 = (bytecblock 0) >>= push -- bytec_0
execute 0x29 = (bytecblock 1) >>= push -- bytec_1
execute 0x2a = (bytecblock 2) >>= push -- bytec_2
execute 0x2b = (bytecblock 3) >>= push -- bytec_3
{-
execute 0x2c = (readUint8 >>= argument) >>= push -- arg
execute 0x2d = (argument 0) >>= push -- arg_0
execute 0x2e = (argument 1) >>= push -- arg_1
execute 0x2f = (argument 2) >>= push -- arg_2
execute 0x30 = (argument 3) >>= push -- arg_3
-}
execute 0x31 = (readUint8 >>= transaction) >>= push -- txn
execute 0x32 = (readUint8 >>= global) >>= push -- global
execute 0x33 = do -- gtxn
  gi <- readUint8
  fi <- readUint8
  (groupTransaction gi fi) >>= push
execute 0x34 = (readUint8 >>= load) >>= push -- load
execute 0x35 = do -- store
  i <- readUint8
  x <- pop
  (store i x)
{-
execute 0x36 = do -- txna
  logicSigVersionGE 2 "txna"
  fi <- readUint8
  fai <- readUint8
  (transactionArray fi fai) >>= push
-}
execute 0x37 = do -- gtxna
  logicSigVersionGE 2 "gtxna"
  gi <- readUint8
  fi <- readUint8
  fai <- readUint8
  (groupTransactionArray gi fi fai) >>= push
{-
execute 0x38 = do -- gtxns
  logicSigVersionGE 3 "gtxns"
  fi <- readUint8
  gi <- pop
  (group_transaction gi fi) >>= push
execute 0x39 = do -- gtxnsa
  logicSigVersionGE 3 "gtxnsa"
  fi <- readUint8
  fai <- readUint8
  gi <- pop
  (group_transaction_array gi fi fai) >>= push
execute 0x3a = do -- gload
  -- "fails unless the requested transaction is an ApplicationCall and X < GroupIndex"
  logicSigVersionGE 4 "gload"
  inMode Application
  gi <- readUint8
  i <- readUint8
  (group_load gi i) >>= push
execute 0x3b = do -- gloads
  -- "fails unless the requested transaction is an ApplicationCall and T < GroupIndex"
  logicSigVersionGE 4 "gloads"
  inMode Application
  i <- readUint8
  gi <- pop
  (group_load gi i) >>= push
execute 0x3c = stub "gaid"
execute 0x3d = do -- gaids
  logicSigVersionGE 4 "gaids"
  inMode Application
  stub "gaids"
-- 0x3e, 0x3f unused
-}
execute 0x40 = do -- bnz
  offset <- readInt16
  huh <- pop >>= isZero
  if not huh then jump offset else continue
execute 0x41 = do -- bz
  offset <- readInt16
  huh <- pop >>= isZero
  if huh then jump offset else continue
execute 0x42 = do -- b
  logicSigVersionGE 2 "b"
  readInt16 >>= jump
execute 0x43 = do -- return
  logicSigVersionGE 2 "return"
  pop >>= finish
execute 0x44 = do -- assert
  logicSigVersionGE 3 "assert"
  huh <- pop >>= isZero
  if huh then fail "assert zero" else continue
{-
-- 0x45, 0x46, 0x47
execute 0x48 = pop >> continue -- pop
execute 0x49 = do -- dup
  x <- pop
  push x
  push x
execute 0x4a = do -- dup2
  b <- pop
  a <- pop
  push a
  push b
  push a
  push b
execute 0x4b = do -- dig
  logicSigVersionGE 3 "dig"
  (readUint8 >>= loop) >>= push
    where loop n =
            do
              x <- pop
              if n == 0
                then
                do
                  push x
                  return x
                else
                do
                  y <- loop $ n - 1
                  push x
                  return y
execute 0x4c = do -- swap
  logicSigVersionGE 3 "swap"
  b <- pop
  a <- pop
  push b
  push a
execute 0x4d = do -- select
  logicSigVersionGE 3 "select"
  c <- pop
  b <- pop
  a <- pop
  huh <- isZero c
  push $ if huh then b else a
execute 0x50 = stub "concat"
execute 0x51 = stub "substring"
execute 0x52 = stub "substring3"
execute 0x53 = stub "getbit"
execute 0x54 = stub "setbit"
execute 0x55 = stub "getbyte"
execute 0x56 = stub "setbyte"
execute 0x57 = stub "extract"
execute 0x58 = stub "extract3"
execute 0x59 = stub "extract16bits"
execute 0x5a = stub "extract32bits"
execute 0x5b = stub "extract64bits"
-- 0x5c, 0x5d, 0x5e, 0x5f
execute 0x60 = stub "balance"
execute 0x61 = stub "app_opted_in"
execute 0x62 = stub "app_local_get"
execute 0x63 = stub "app_local_get_ex"
-}
execute 0x64 = do
  logicSigVersionGE 2 "app_global_get"
  inMode Application "app_global_get"
  (pop >>= appGlobalGet) >>= push
{-
execute 0x65 = stub "app_global_get_ex"
execute 0x66 = stub "app_local_put"
-}
execute 0x67 = do
  logicSigVersionGE 2 "app_global_put"
  inMode Application "app_global_put"
  b <- pop
  a <- pop
  appGlobalPut a b
{-
execute 0x68 = stub "app_local_del"
execute 0x69 = stub "app_global_del"
execute 0x70 = stub "asset_holding_get"
execute 0x71 = stub "asset_params_get"
execute 0x72 = stub "app_params_get"
-- 0x73, 0x74, 0x75, 0x76, 0x77
execute 0x78 = stub "min_balance"
-- 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f
execute 0x80 = do -- pushbytes
  logicSigVersionGE 3 "pushbytes"
  readBytes >>= push
execute 0x81 = do -- pushint
  logicSigVersionGE 3 "pushint"
  readVaruint >>= push
-- 0x82, 0x83, 0x84, 0x85, 0x86, 0x87
execute 0x88 = do -- callsub
  logicSigVersionGE 4 "callsub"
  readInt16 >>= callsub
execute 0x89 = do -- retsub
  logicSigVersionGE 4 "retsub"
  retsub
execute 0x90 = stub "shl"
execute 0x91 = stub "shr"
execute 0x92 = stub "sqrt"
execute 0x93 = stub "bitlen"
execute 0x94 = stub "exp"
execute 0x95 = stub "expw"
-- 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f
execute 0xa0 = stub "b+"
execute 0xa1 = stub "b-"
execute 0xa2 = stub "b/"
execute 0xa3 = stub "b*"
execute 0xa4 = stub "b<"
execute 0xa5 = stub "b>"
execute 0xa6 = stub "b<="
execute 0xa7 = stub "b>="
execute 0xa8 = stub "b=="
execute 0xa9 = stub "b!="
execute 0xaa = stub "b%"
execute 0xab = stub "b|"
execute 0xac = stub "b&"
execute 0xad = stub "b^"
execute 0xae = stub "b~"
execute 0xaf = stub "bzero"
-}
-- the rest are unused
execute oc = unused oc

{-
import Data.Functor
import Control.Monad (liftM)
import ReadByte

type Code = Integer

data Result s a = Partial s a | Success Code | Failure String

data VM s a = ThisVM (s -> Result s a)

instance Functor (VM s) where
  fmap = liftM

instance Applicative (VM s) where
  pure x = ThisVM $ \s -> Partial s x

instance Monad (VM s) where
  (ThisVM m) >>= f = ThisVM $ \s -> case (m s) of
                                      Partial s x -> let ThisVM m = f x in m s
                                      Success c -> Success c
                                      Failure s -> Failure s

instance ReadByte (VM s) where
  readByte = ThisVM $ \s -> Partial s 42

--class Monad m => VM m s a where
--  push :: Integer -> m a

isZero x = ThisVM $ \s -> Partial s True

readBytes = ThisVM $ \s -> Partial s 42

continue = ThisVM $ \s -> Partial s 42

finish x = ThisVM $ \s -> Success x
fail msg = ThisVM $ \s -> Failure msg

jump x = ThisVM $ \s -> Partial s 42

transaction fi = ThisVM $ \s -> Partial s 42

global i = ThisVM $ \s -> Partial s 42

load i = ThisVM $ \s -> Partial s 42
store i x = ThisVM $ \s -> Partial s 42

group_load gi i = ThisVM $ \s -> Partial s 42

transaction_array fi fai = ThisVM $ \s -> Partial s 42

group_transaction gi fi = ThisVM $ \s -> Partial s 42
group_transaction_array gi fi fai = ThisVM $ \s -> Partial s 42

argument i = ThisVM $ \s -> Partial s 42

intcblock i = ThisVM $ \s -> Partial s 42
putIntcblock xs = ThisVM $ \s -> Partial s 42

bytecblock i = ThisVM $ \s -> Partial s 42
putBytecblock bss = ThisVM $ \s -> Partial s 42

data Mode = LogicSig | Application
  deriving Eq

inMode mode = ThisVM $ \s -> Partial s 42
-}
