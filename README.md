# leaderlog-Script
Leaderlog semi-auto

need env file

**Script workflow**
- calculate the next epoch leaderlog
- create json file for each epoch
- write to cntools db
- if db already exist read from json file

** Make Sure you have your env file **

## INSTRUCTIONS

 **Run** the script
```
./leaderlog.sh
```



## More info
the script is semi-auto, it need you to be involved in the order of executing, folders name, delete duplicate files ect..
If you already executed `leaderlog.sh` it will auto create a json file for the next epoch. if you want to force run `leaderlog.sh` again you need to delete/move the next epoch json file before you execute

## Contributing

Thank you for your interest in [ARARE](https://arare.io) NFT Script! Head over to our [Telegram](https://t.me/ararestakepool) for instructions on how to use and for asking changes!


#### Support

To report **bugs** and **issues** with scripts and documentation please join our [Telegram Chat](https://t.me/ararestakepool) **or** [GitHub Issue](https://github.com/ARARE-pool/leaderlog/issues/new/choose).  
**Feature requests** are best opened as a [discussion thread](https://github.com/ARARE-pool/leaderlog/discussions/new).

<i>inspired by cntools code</i>
