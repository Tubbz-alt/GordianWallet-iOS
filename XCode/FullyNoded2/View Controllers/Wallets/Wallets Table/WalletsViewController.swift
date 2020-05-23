//
//  WalletsViewController.swift
//  StandUp-Remote
//
//  Created by Peter on 10/01/20.
//  Copyright © 2020 Blockchain Commons, LLC. All rights reserved.
//

import UIKit

class WalletsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UINavigationControllerDelegate {
    
    weak var nodeLogic = NodeLogic.sharedInstance
    var walletName = ""
    var walletToImport = [String:Any]()
    var isLoading = Bool()
    var refresher: UIRefreshControl!
    var index = Int()
    var name = ""
    var node:NodeStruct!
    var wallets = [[String:Any]]()
    var wallet:WalletStruct!
    var sortedWallets = [[String:Any]]()
    let dateFormatter = DateFormatter()
    let creatingView = ConnectingView()
    var nodes = [[String:Any]]()
    var recoveryPhrase = ""
    var descriptor = ""
    var fullRefresh = Bool()
    @IBOutlet var walletTable: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.delegate = self
        walletTable.delegate = self
        walletTable.dataSource = self
        configureRefresher()
        walletTable.setContentOffset(.zero, animated: true)
        NotificationCenter.default.addObserver(self, selector: #selector(didSweep(_:)), name: .didSweep, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // MARK: TODO - Add a notification when a signer or seed gets added to refresh
        fullRefresh = true
        refresh()
    }
    
    @IBAction func scanQr(_ sender: Any) {
        DispatchQueue.main.async { [unowned vc = self] in
            vc.performSegue(withIdentifier: "goImport", sender: vc)
        }
    }
    
    @IBAction func accountTools(_ sender: Any) {
        if wallet != nil {
            walletTools()
        } else {
            showAlert(vc: self, title: "No active account", message: "Tap an account to activate it, then you can use tools. If you don't have any accounts create one by tapping the + button or import one by tapping the QR scanner.")
        }
    }
    
    @IBAction func addAccount(_ sender: Any) {
        createWallet()
    }
    
    @objc func didSweep(_ notification: Notification) {
        creatingView.addConnectingView(vc: self, description: "refreshing your wallets data")
        fullRefresh = true
        refresh()
    }
    
    private func configureRefresher() {
        refresher = UIRefreshControl()
        refresher.tintColor = UIColor.white
        refresher.attributedTitle = NSAttributedString(string: "refresh data", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white])
        refresher.addTarget(self, action: #selector(self.reloadActiveWallet), for: UIControl.Event.valueChanged)
        walletTable.addSubview(refresher)
    }
    
    func onionAddress(wallet: WalletStruct) -> String {
        
        var rpcOnion = ""
    
        for n in nodes {
            
            let s = NodeStruct(dictionary: n)
            
            if s.id == wallet.nodeId {
                
                rpcOnion = s.onionAddress
                
            }
            
        }
        
        return rpcOnion
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        
        nodes.removeAll()
        
    }
    
    func refresh() {
        print("refresh")
        
        sortedWallets.removeAll()
        
        func loadWallets() {
            
            creatingView.addConnectingView(vc: self, description: "loading accounts")
                        
            CoreDataService.retrieveEntity(entityName: .wallets) { [unowned vc = self] (wallets, errorDescription) in
                print("wallets = \(wallets)")
                                                
                if errorDescription == nil {
                    
                    if wallets!.count == 0 {
                        
                        vc.creatingView.removeConnectingView()
                        vc.isLoading = false
                        
                    } else {
                        
                        for (i, w) in wallets!.enumerated() {
                            
                            let s = WalletStruct(dictionary: w)
                            
                            if !s.isArchived && w["id"] != nil && w["name"] != nil {
                                vc.sortedWallets.append(w)
                                if s.isActive {
                                    vc.wallet = s
                                }
                            }
                                                        
                            if i + 1 == wallets!.count {
                                print("sorted wallets = \(vc.sortedWallets)")
                                
                                if vc.sortedWallets.count == 0 {
                                    vc.creatingView.removeConnectingView()
                                    vc.isLoading = false
                                }
                                
                                for (i, wallet) in vc.sortedWallets.enumerated() {
                                    let wstruct = WalletStruct(dictionary: wallet)
                                    
                                    SeedParser.parseWallet(wallet: wstruct) { (known, unknown) in
                                        if known != nil && unknown != nil {
                                            vc.sortedWallets[i]["knownSigners"] = known!
                                            vc.sortedWallets[i]["unknownSigners"] = unknown!
                                        }
                                        
                                        SeedParser.fetchSeeds(wallet: wstruct) { (words, fingerprints) in
                                            if fingerprints != nil {
                                                vc.sortedWallets[i]["knownFingerprints"] = fingerprints!
                                            }
                                            
                                            if i + 1 == vc.sortedWallets.count {
                                                
                                                vc.sortedWallets = vc.sortedWallets.sorted{ ($0["lastUsed"] as? Date ?? Date()) > ($1["lastUsed"] as? Date ?? Date()) }
                                                
                                                if vc.sortedWallets.count == 0 {
                                                    
                                                    vc.isLoading = false
                                                    vc.createWallet()
                                                    
                                                } else {
                                                    
                                                    if vc.nodes.count == 0 {
                                                        
                                                        vc.isLoading = false
                                                        vc.walletTable.isUserInteractionEnabled = false
                                                        
                                                        for (i, wallet) in vc.sortedWallets.enumerated() {
                                                            
                                                            let w = WalletStruct(dictionary: wallet)
                                                            CoreDataService.updateEntity(id: w.id!, keyToUpdate: "isActive", newValue: false, entityName: .wallets) {_ in }
                                                            
                                                            if i + 1 == vc.sortedWallets.count {
                                                                
                                                                DispatchQueue.main.async {
                                                                    vc.creatingView.removeConnectingView()
                                                                    vc.walletTable.reloadData()
                                                                }
                                                                
                                                            }
                                                            
                                                        }
                                                        
                                                    } else {
                                                        print("we here")
                                                        func reloadNow() {
                                                            DispatchQueue.main.async { [unowned vc = self] in
                                                                vc.walletTable.reloadData()
                                                                vc.creatingView.removeConnectingView()
                                                                vc.walletTable.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
                                                                vc.fullRefresh = false
                                                                vc.isLoading = false
                                                            }
                                                        }
                                                        
                                                        let account = WalletStruct(dictionary: vc.sortedWallets[0])
                                                        vc.getWalletBalance(walletStruct: account) {
                                                            reloadNow()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                } else {
                    vc.creatingView.removeConnectingView()
                    displayAlert(viewController: vc, isError: true, message: errorDescription!)
                    
                }
            }
        }
        
        CoreDataService.retrieveEntity(entityName: .nodes) { [unowned vc = self] (nodes, errorDescription) in
            
            if errorDescription == nil && nodes != nil {
                
                if nodes!.count > 0 {
                    
                    vc.nodes = nodes!
                    
                    for (i, n) in nodes!.enumerated() {
                        
                        Encryption.decryptData(dataToDecrypt: (n["onionAddress"] as! Data)) { (decryptedOnionAddress) in
                            
                            if decryptedOnionAddress != nil {
                                
                                vc.nodes[i]["onionAddress"] = String(bytes: decryptedOnionAddress!, encoding: .utf8)
                                
                            }
                            
                            Encryption.decryptData(dataToDecrypt: (n["label"] as! Data)) { (decryptedLabel) in
                            
                                if decryptedLabel != nil {
                                    
                                    vc.nodes[i]["label"] = String(bytes: decryptedLabel!, encoding: .utf8)
                                    
                                }
                                
                            }
                            
                            if i + 1 == nodes!.count {
                                
                                loadWallets()
                                
                            }
                            
                        }
                                            
                    }
                    
                } else {
                    
                    loadWallets()
                    
                    displayAlert(viewController: vc, isError: true, message: "no nodes! Something is very wrong, you will not be able to use these wallets without a node")
                    
                }
                
            }
            
        }
                
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return 1
        
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        
        if sortedWallets.count == 0 {
            
            return 1
            
        } else {
            
            return sortedWallets.count
            
        }
        
    }
    
    private func singleSigCell(_ indexPath: IndexPath) -> UITableViewCell {
        
        let d = sortedWallets[indexPath.section]
        let walletStruct = WalletStruct.init(dictionary: d)
        
        let cell = walletTable.dequeueReusableCell(withIdentifier: "singleSigWalletCell", for: indexPath)
        cell.selectionStyle = .none
        
        let balanceLabel = cell.viewWithTag(1) as! UILabel
        let updatedLabel = cell.viewWithTag(13) as! UILabel
        let createdLabel = cell.viewWithTag(14) as! UILabel
        let rpcOnionLabel = cell.viewWithTag(19) as! UILabel
        let walletFileLabel = cell.viewWithTag(20) as! UILabel
        let seedOnDeviceView = cell.viewWithTag(21)!
        let nodeView = cell.viewWithTag(26)!
        let nodeLabel = cell.viewWithTag(27) as! UILabel
        let deviceXprv = cell.viewWithTag(28) as! UILabel
        let bannerView = cell.viewWithTag(32)!
        let nodeKeysLabel = cell.viewWithTag(33) as! UILabel
        let seedOnDeviceLabel = cell.viewWithTag(37) as! UILabel
        let deviceSeedImage = cell.viewWithTag(38) as! UIImageView
        let walletTypeLabel = cell.viewWithTag(39) as! UILabel
        let walletTypeImage = cell.viewWithTag(40) as! UIImageView
        let accountLabel = cell.viewWithTag(42) as! UILabel
        let typeLabel = cell.viewWithTag(43) as! UILabel
        
        accountLabel.text = walletStruct.label
        balanceLabel.adjustsFontSizeToFitWidth = true
        balanceLabel.text = "\(walletStruct.lastBalance.avoidNotation) BTC"
        
        if walletStruct.isActive {
            
            cell.contentView.alpha = 1
            bannerView.backgroundColor = #colorLiteral(red: 0, green: 0.1631944358, blue: 0.3383367703, alpha: 1)
            
        } else if !walletStruct.isActive {
            
            cell.contentView.alpha = 0.4
            bannerView.backgroundColor = #colorLiteral(red: 0.1051254794, green: 0.1292803288, blue: 0.1418488324, alpha: 1)
            
        }
        
        if let isRescanning = sortedWallets[indexPath.section]["isRescanning"] as? Bool {
            
            if isRescanning {
                
                if let progress = sortedWallets[indexPath.section]["progress"] as? String {
                    
                    balanceLabel.text = "Rescanning... \(progress)%"
                    
                }
                                
            }
            
        }
        
        nodeView.layer.cornerRadius = 8
        seedOnDeviceView.layer.cornerRadius = 8
        
        let derivation = walletStruct.derivation
        
        if derivation.contains("1") {
            
            balanceLabel.textColor = .systemOrange
            
        } else {
            
            balanceLabel.textColor = .systemGreen
            
        }
        
        let descriptorParser = DescriptorParser()
        let descriptorStruct = descriptorParser.descriptor(walletStruct.descriptor)
        let fingerprint = descriptorStruct.fingerprint
                
        if walletStruct.knownSigners == 1 {
            
            seedOnDeviceLabel.text = "1 Seed on \(UIDevice.current.name)"
            deviceXprv.text = "1 root xprv: \(fingerprint)"
            deviceSeedImage.image = UIImage(imageLiteralResourceName: "Signature")
            walletTypeLabel.text = "Hot Account"
            walletTypeImage.image = UIImage(systemName: "flame")
            walletTypeImage.tintColor = .systemRed
            
        } else {
            
            seedOnDeviceLabel.text = "\(UIDevice.current.name) is cold"
            deviceXprv.text = "1 account xpub: \(fingerprint)"
            deviceSeedImage.image = UIImage(systemName: "eye.fill")
            walletTypeLabel.text = "Cold Account"
            walletTypeImage.image = UIImage(systemName: "snow")
            walletTypeImage.tintColor = .white
            
        }
        
        nodeKeysLabel.text = "Keypool \(walletStruct.index) to \(walletStruct.maxRange)"
        updatedLabel.text = "\(formatDate(date: walletStruct.lastUpdated))"
        createdLabel.text = "\(getDate(unixTime: walletStruct.birthdate))"
        walletFileLabel.text = reducedWalletName(name: walletStruct.name!)
        
        if derivation.contains("84") {

            typeLabel.text = "Single Sig - Segwit"

        } else if derivation.contains("44") {

            typeLabel.text = "Single Sig - Legacy"

        } else if derivation.contains("49") {

            typeLabel.text = "Single Sig - Nested Segwit"

        } else {
            
            typeLabel.text = "Single Sig - Custom"
        }
        
        for n in nodes {
            
            let s = NodeStruct(dictionary: n)
            
            if s.id == walletStruct.nodeId {
                
                let rpcOnion = s.onionAddress
                let first10 = String(rpcOnion.prefix(5))
                let last15 = String(rpcOnion.suffix(15))
                rpcOnionLabel.text = "\(first10)*****\(last15)"
                nodeLabel.text = s.label
                
            }
            
        }
        
        return cell
        
    }
    
    private func multiSigWalletCell(_ indexPath: IndexPath) -> UITableViewCell {
        
        let d = sortedWallets[indexPath.section]
        let walletStruct = WalletStruct.init(dictionary: d)
        
        let cell = walletTable.dequeueReusableCell(withIdentifier: "multiSigWalletCell", for: indexPath)
        cell.selectionStyle = .none
        
        let balanceLabel = cell.viewWithTag(1) as! UILabel
        let updatedLabel = cell.viewWithTag(13) as! UILabel
        let createdLabel = cell.viewWithTag(14) as! UILabel
        let rpcOnionLabel = cell.viewWithTag(19) as! UILabel
        let walletFileLabel = cell.viewWithTag(20) as! UILabel
        let seedOnDeviceView = cell.viewWithTag(21)!
        let seedOnNodeView = cell.viewWithTag(22)!
        let seedOfflineView = cell.viewWithTag(23)!
        let nodeView = cell.viewWithTag(26)!
        let nodeLabel = cell.viewWithTag(27) as! UILabel
        let deviceXprv = cell.viewWithTag(29) as! UILabel
        let nodeKeys = cell.viewWithTag(30) as! UILabel
        let offlineXprv = cell.viewWithTag(31) as! UILabel
        let bannerView = cell.viewWithTag(33)!
        let seedOnDeviceLabel = cell.viewWithTag(36) as! UILabel
        let offlineSeedLabel = cell.viewWithTag(37) as! UILabel
        let mOfnTypeLabel = cell.viewWithTag(38) as! UILabel
        let walletType = cell.viewWithTag(39) as! UILabel
        let walletTypeImage = cell.viewWithTag(40) as! UIImageView
        let deviceSeedImage = cell.viewWithTag(41) as! UIImageView
        let accountLabel = cell.viewWithTag(42) as! UILabel
        let primaryKeysNodeSignerImage = cell.viewWithTag(43) as! UIImageView
        
        accountLabel.text = walletStruct.label
        let p = DescriptorParser()
        let str = p.descriptor(walletStruct.descriptor)
        balanceLabel.adjustsFontSizeToFitWidth = true
        balanceLabel.text = "\(walletStruct.lastBalance.avoidNotation) BTC"
                
        if let isRescanning = sortedWallets[indexPath.section]["isRescanning"] as? Bool {
            
            if isRescanning {
                
                if let progress = sortedWallets[indexPath.section]["progress"] as? String {
                    
                    balanceLabel.text = "Rescanning... \(progress)%"
                    
                }
                                
            }
            
        }
        
        if walletStruct.isActive {
            
            cell.contentView.alpha = 1
            bannerView.backgroundColor = #colorLiteral(red: 0, green: 0.1631944358, blue: 0.3383367703, alpha: 1)
            
        } else if !walletStruct.isActive {
            
            cell.contentView.alpha = 0.6
            bannerView.backgroundColor = #colorLiteral(red: 0.1051254794, green: 0.1292803288, blue: 0.1418488324, alpha: 1)
            
        }
        
        nodeView.layer.cornerRadius = 8
        seedOnDeviceView.layer.cornerRadius = 8
        seedOnNodeView.layer.cornerRadius = 8
        seedOfflineView.layer.cornerRadius = 8
        
        let derivation = walletStruct.derivation
        
        if derivation.contains("1") {
            
            balanceLabel.textColor = .systemOrange
            
        } else {
            
            balanceLabel.textColor = .systemGreen
            
        }
        
        if derivation.contains("84") {
            
            mOfnTypeLabel.text = "\(str.mOfNType) multisig - Segwit"
            
        } else if derivation.contains("44") {
            
            mOfnTypeLabel.text = "\(str.mOfNType) multisig - Legacy"
            
        } else if derivation.contains("49") {
            
            mOfnTypeLabel.text = "\(str.mOfNType) multisig - Nested Segwit"
            
        } else if derivation.contains("48") {
            
            mOfnTypeLabel.text = "\(str.mOfNType) multisig - Segwit"
            
        } else {
            
            mOfnTypeLabel.text = "\(str.mOfNType) multisig - Custom"
            
        }
        
        if walletStruct.nodeIsSigner != nil {
            if walletStruct.nodeIsSigner! {
                primaryKeysNodeSignerImage.image = UIImage(imageLiteralResourceName: "Signature")
                
            } else {
                primaryKeysNodeSignerImage.image = UIImage(systemName: "eye.fill")
                
            }
            
        } else {
            primaryKeysNodeSignerImage.image = UIImage(imageLiteralResourceName: "Signature")
            
        }
        
        let descriptorParser = DescriptorParser()
        let descriptorStruct = descriptorParser.descriptor(walletStruct.descriptor)
        let processedFingerprint = process(walletStruct.knownFingerprints ?? [""])
        var unknownFingerprints = descriptorStruct.fingerprint.replacingOccurrences(of: processedFingerprint + ",", with: "")
        unknownFingerprints = unknownFingerprints.replacingOccurrences(of: ", " + processedFingerprint, with: "")
                
        if walletStruct.knownSigners == str.sigsRequired {
            
            var signer = "Seed"
            if walletStruct.knownSigners > 1 {
                signer = "Seeds"
            }
            
            seedOnDeviceLabel.text = "\(walletStruct.knownSigners) \(signer) on \(UIDevice.current.name)"
            walletType.text = "Hot Account"
            walletTypeImage.image = UIImage(systemName: "flame")
            walletTypeImage.tintColor = .systemRed
            deviceSeedImage.image = UIImage(imageLiteralResourceName: "Signature")
            deviceXprv.text = "root xprv's: \(processedFingerprint)"
            
        } else if walletStruct.knownSigners == 0 {
            
            seedOnDeviceLabel.text = "0 Seed's on \(UIDevice.current.name)"
            walletType.text = "Cool Account"
            walletTypeImage.image = UIImage(systemName: "cloud.sun")
            walletTypeImage.tintColor = .systemTeal
            deviceSeedImage.image = UIImage(systemName: "eye.fill")
            deviceXprv.text = "xpub's: \(unknownFingerprints)"
            
        } else if walletStruct.knownSigners < str.sigsRequired {
            
            seedOnDeviceLabel.text = "\(walletStruct.knownSigners) Seed on \(UIDevice.current.name)"
            walletType.text = "Warm Account"
            walletTypeImage.image = UIImage(systemName: "sun.min")
            walletTypeImage.tintColor = .systemYellow
            deviceSeedImage.image = UIImage(imageLiteralResourceName: "Signature")
            deviceXprv.text = "root xprv: \(processedFingerprint)"
            
        }
        
        offlineSeedLabel.text = "\(walletStruct.unknownSigners) external seed's"
        offlineXprv.text = "xprv's: \(unknownFingerprints)"
        nodeKeys.text = "Keypool \(walletStruct.index) to \(walletStruct.maxRange)"
        
        updatedLabel.text = "\(formatDate(date: walletStruct.lastUpdated))"
        createdLabel.text = "\(getDate(unixTime: walletStruct.birthdate))"
        walletFileLabel.text = reducedWalletName(name: walletStruct.name!)
        
        for n in nodes {
            
            let s = NodeStruct(dictionary: n)
            
            if s.id == wallet.nodeId {
                
                let rpcOnion = s.onionAddress
                let first10 = String(rpcOnion.prefix(5))
                let last15 = String(rpcOnion.suffix(15))
                rpcOnionLabel.text = "\(first10)*****\(last15)"
                nodeLabel.text = s.label
                
            }
            
        }
        
        return cell
        
    }
    
    private func process(_ fingerprints:[String]) -> String {
        var processed = fingerprints.description.replacingOccurrences(of: "[", with: "")
        processed = processed.replacingOccurrences(of: "]", with: "")
        processed = processed.replacingOccurrences(of: "\"", with: "")
        return processed
    }
        
    private func noWalletCell() -> UITableViewCell {
        
        let cell = UITableViewCell()
        cell.backgroundColor = .black
        cell.textLabel?.text = "⚠︎ No account's created yet, tap the +"
        cell.textLabel?.textColor = .lightGray
        cell.textLabel?.font = .systemFont(ofSize: 17)
        return cell
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if sortedWallets.count > 0 {
            
            let d = sortedWallets[indexPath.section]
            let walletStruct = WalletStruct.init(dictionary: d)
                
            switch walletStruct.type {
                
            case "DEFAULT":
                
                return singleSigCell(indexPath)
                
            case "MULTI":
                
                return multiSigWalletCell(indexPath)
                
            default:
                
                return UITableViewCell()
                
            }
            
        } else {
            
            return noWalletCell()
            
        }
        
    }
    
    @objc func exportSeed(_ sender: UIButton) {
        
        let isCaptured = UIScreen.main.isCaptured
        
        if !isCaptured {
            
            DispatchQueue.main.async { [unowned vc = self] in
                
                vc.performSegue(withIdentifier: "exportSeed", sender: vc)
                
            }
            
        } else {
            
            showAlert(vc: self, title: "Security Alert!", message: "Your device is taking a screen recording, please stop the recording and try again.")
            
        }        
                
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        if sortedWallets.count > 0 {
            
            let type = WalletStruct(dictionary: sortedWallets[indexPath.section]).type
            
            switch  type {
                
            case "DEFAULT":
                
                return 320
                
            case "MULTI":
                
                return 354
                
            default:
                
                return 0
                
            }
            
        } else {
            
            return 80
            
        }
                
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        
        return 30
        
    }
    
    @objc func walletTools() {
        if !isLoading {
            DispatchQueue.main.async { [unowned vc = self] in
                vc.performSegue(withIdentifier: "goToTools", sender: vc)
            }
        } else {
            showAlert(vc: self, title: "Please be patient", message: "We are fetching data from your node, wait until the spinner disappears then try again.")
        }
    }
    
    @objc func reloadActiveWallet() {

        if !isLoading {
            refresher.beginRefreshing()
            isLoading = true

            DispatchQueue.main.async { [unowned vc = self] in
                vc.creatingView.addConnectingView(vc: vc, description: "refreshing wallet data...")
            }

            let walletStruct = WalletStruct(dictionary: self.sortedWallets[index])

            nodeLogic?.loadWalletData(wallet: walletStruct) { [unowned vc = self] (success, dictToReturn, errorDesc) in

                if success && dictToReturn != nil {

                    let s = HomeStruct(dictionary: dictToReturn!)
                    let doub = (s.coldBalance).doubleValue

                    vc.sortedWallets[0]["lastBalance"] = doub
                    vc.sortedWallets[0]["lastUsed"]  = Date()
                    vc.sortedWallets[0]["lastUpdated"] = Date()

                    vc.getRescanStatus(walletName: WalletStruct(dictionary: vc.sortedWallets[0]).name ?? "") {
                        DispatchQueue.main.async { [unowned vc = self] in
                            vc.walletTable.reloadData()
                            vc.isLoading = false
                            vc.creatingView.removeConnectingView()
                            vc.refresher.endRefreshing()
                        }
                    }

                } else {

                    DispatchQueue.main.async { [unowned vc = self] in
                        vc.walletTable.reloadSections(IndexSet(arrayLiteral: 0), with: .fade)
                        vc.isLoading = false
                        vc.refresh()
                        vc.creatingView.removeConnectingView()
                        vc.refresher.endRefreshing()
                        showAlert(vc: self, title: "Error", message: errorDesc ?? "error updating balance")
                    }

                }

            }

        } else {

            showAlert(vc: self, title: "Please be patient", message: "We are fetching data from your node, wait until the spinner disappears then try again.")

        }

    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if sortedWallets.count > 0 {
         
            let dict = sortedWallets[indexPath.section]
            let walletStruct = WalletStruct.init(dictionary: dict)
            
            if !walletStruct.isActive {
                
                UIView.animate(withDuration: 0.3) { [unowned vc = self] in
                    vc.walletTable.alpha = 0
                }
                
                activateNow(wallet: walletStruct, index: indexPath.section)
                
            }
            
        }
        
    }
    
    func activateNow(wallet: WalletStruct, index: Int) {
        
        if !wallet.isActive {
                        
            Encryption.getNode { [unowned vc = self] (n, error) in
                
                if n != nil {
                    
                    if wallet.nodeId != n!.id {
                        
                        CoreDataService.updateEntity(id: wallet.nodeId, keyToUpdate: "isActive", newValue: true, entityName: .nodes) {_ in }
                        CoreDataService.updateEntity(id: n!.id, keyToUpdate: "isActive", newValue: false, entityName: .nodes) {_ in }
                        vc.wallet = wallet
                        
                    }
                    
                }
                
            }
            
            CoreDataService.updateEntity(id: wallet.id!, keyToUpdate: "lastUsed", newValue: Date(), entityName: .wallets) { [unowned vc = self] _ in
                
                vc.activate(walletToActivate: wallet.id!, index: index)
                
            }
            
        }
        
    }
    
    func getDate(unixTime: Int32) -> String {
        
        let date = Date(timeIntervalSince1970: TimeInterval(unixTime))
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MMM-dd hh:mm"
        let strDate = dateFormatter.string(from: date)
        return strDate
        
    }
    
    func formatDate(date: Date) -> String {
        
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MMM-dd hh:mm"
        let strDate = dateFormatter.string(from: date)
        return strDate
        
    }
    
    func activate(walletToActivate: UUID, index: Int) {
        
        CoreDataService.updateEntity(id: walletToActivate, keyToUpdate: "isActive", newValue: true, entityName: .wallets) { [unowned vc = self] (success, errorDesc) in
            
            if success {
                                        
                vc.deactivate(walletToActivate: walletToActivate, index: index)
                
            } else {
                
                displayAlert(viewController: vc, isError: true, message: "error deactivating account")
                
            }
            
        }
        
    }
    
    func deactivate(walletToActivate: UUID, index: Int) {
        
        for (i, wallet) in sortedWallets.enumerated() {
            
            let str = WalletStruct.init(dictionary: wallet)
            
            if str.id != walletToActivate {
                
                CoreDataService.updateEntity(id: str.id!, keyToUpdate: "isActive", newValue: false, entityName: .wallets) { [unowned vc = self] (success, errorDesc) in
                    
                    if !success {
                        
                        displayAlert(viewController: vc, isError: true, message: "error deactivating account")
                        
                    }
                    
                }
                
            }
            
            if i + 1 == sortedWallets.count {
                
                fullRefresh = false
                refresh()
                
                UIView.animate(withDuration: 1.5) { [unowned vc = self] in
                    vc.walletTable.alpha = 1
                }
                
                NotificationCenter.default.post(name: .didSwitchAccounts, object: nil, userInfo: nil)
                                            
            }
            
        }
        
    }
    
    @objc func createWallet() {
        
        if !isLoading {
            
            // MARK: - To enable mainnet accounts just uncomment the following lines of code:
            
            DispatchQueue.main.async { [unowned vc = self] in

                vc.performSegue(withIdentifier: "addWallet", sender: vc)

            }
            
            // MARK: - And comment the following lines of code:
            
            // ---------------------------------------------------
            
//            Encryption.getNode { [unowned vc = self] (node, error) in
//
//                if !error && node != nil {
//
//                    if node!.network == "mainnet" {
//
//                        DispatchQueue.main.async {
//
//                            let alert = UIAlertController(title: "We appreciate your patience", message: "We are still adding new features, so mainnet wallets are disabled. Please help us test.", preferredStyle: .actionSheet)
//
//                            alert.addAction(UIAlertAction(title: "Understood", style: .default, handler: { [unowned vc = self] action in }))
//
//                            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
//
//                            self.present(alert, animated: true, completion: nil)
//
//                        }
//
//                    } else {
//
//                        DispatchQueue.main.async {
//
//                            vc.performSegue(withIdentifier: "addWallet", sender: vc)
//
//                        }
//
//                    }
//
//                } else {
//
//                    displayAlert(viewController: vc, isError: true, message: "No active nodes")
//
//                }
//
//            }
            
            // ---------------------------------------------------
            
        } else {
            
            showAlert(vc: self, title: "Fetching wallet data from your node...", message: "Please wait until the spinner disappears as the app is currently fetching wallet data from your node.")
            
        }
        
    }
    
    func getWalletBalance(walletStruct: WalletStruct, completion: @escaping () -> Void) {
        print("getWalletBalance")
        nodeLogic?.loadWalletData(wallet: walletStruct) { [unowned vc = self] (success, dictToReturn, errorDesc) in
            
            if success && dictToReturn != nil {
                
                let s = HomeStruct(dictionary: dictToReturn!)
                let doub = (s.coldBalance).doubleValue
                
                vc.sortedWallets[0]["lastBalance"] = doub
                vc.getRescanStatus(walletName: walletStruct.name ?? "") {
                    
                    completion()
                                            
                }
                
            } else {
                
                completion()
                
            }
            
        }
        
    }
    
    func getRescanStatus(walletName: String, completion: @escaping () -> Void) {
        
        if sortedWallets.count > 0 {
            
            Reducer.makeCommand(walletName: walletName, command: .getexternalwalletinfo, param: "") { [unowned vc = self] (object, errorDesc) in

                if let result = object as? NSDictionary {

                    if let scanning = result["scanning"] as? NSDictionary {

                        if let _ = scanning["duration"] as? Int {

                            let progress = (scanning["progress"] as! Double) * 100
                            vc.sortedWallets[0]["progress"] = "\(Int(progress))"
                            vc.sortedWallets[0]["isRescanning"] = true
                            completion()

                        }

                    } else {
                        
                        completion()

                    }

                } else {
                    
                    vc.sortedWallets[0]["isRescanning"] = false
                    completion()

                }

            }
            
        } else {
            
            completion()
            
        }
        
    }
    
    private func reducedWalletName(name: String) -> String {
        let first = String(name.prefix(5))
        let last = String(name.suffix(5))
        return "\(first)*****\(last).dat"
        
    }
    
    private func reduceLabel(label: String) -> String {
        let first = String(label.prefix(10))
        let last = String(label.suffix(10))
        return "\(first)...\(last)"
        
    }
    
    override func didRotate(from fromInterfaceOrientation: UIInterfaceOrientation) {
        walletTable.reloadData()
        
    }
    
    private func processDescriptor(descriptor: String) {
        
        let cv = ConnectingView()
        cv.addConnectingView(vc: self, description: "processing...")
        
        if let data = descriptor.data(using: .utf8) {
            
            do {
                
            let dict = try JSONSerialization.jsonObject(with: data, options: []) as! [String:Any]
            
                if let _ = dict["descriptor"] as? String {
                    
                    if let _ = dict["blockheight"] as? Int {
                        /// It is an Account Map.
                        Import.importAccountMap(accountMap: dict) { walletDict in
                            print("importAccountMap")
                            
                            if walletDict != nil {
                                DispatchQueue.main.async { [unowned vc = self] in
                                    cv.removeConnectingView()
                                    vc.walletToImport = walletDict!
                                    vc.walletName = walletDict!["name"] as! String
                                    vc.performSegue(withIdentifier: "goConfirmImport", sender: vc)
                                    
                                }
                            }
                        }
                    }
                } else if let fingerprint = dict["xfp"] as? String {
                    /// It is a coldcard wallet skeleton file.
                    cv.removeConnectingView()
                    DispatchQueue.main.async { [unowned vc = self] in
                        
                        let alert = UIAlertController(title: "Import Coldcard Single-sig account?", message: TextBlurbs.chooseColdcardDerivationToImport(), preferredStyle: .actionSheet)
                        
                        alert.addAction(UIAlertAction(title: "Native Segwit (BIP84, bc1)", style: .default, handler: { action in
                            cv.addConnectingView(vc: vc, description: "importing...")
                            let bip84Dict = dict["bip84"] as! NSDictionary
                            
                            Import.importColdCard(coldcardDict: bip84Dict, fingerprint: fingerprint) { (walletToImport) in
                                
                                if walletToImport != nil {
                                    DispatchQueue.main.async { [unowned vc = self] in
                                        cv.removeConnectingView()
                                        vc.walletName = walletToImport!["name"] as! String
                                        vc.walletToImport = walletToImport!
                                        vc.performSegue(withIdentifier: "goConfirmImport", sender: vc)
                                        
                                    }
                                }
                            }
                            
                        }))
                        
                        alert.addAction(UIAlertAction(title: "Nested Segwit (BIP49, 3)", style: .default, handler: { action in
                            cv.addConnectingView(vc: vc, description: "importing...")
                            let bip49Dict = dict["bip49"] as! NSDictionary
                            
                            Import.importColdCard(coldcardDict: bip49Dict, fingerprint: fingerprint) { (walletToImport) in
                                
                                if walletToImport != nil {
                                    DispatchQueue.main.async { [unowned vc = self] in
                                        cv.removeConnectingView()
                                        vc.walletName = walletToImport!["name"] as! String
                                        vc.walletToImport = walletToImport!
                                        vc.performSegue(withIdentifier: "goConfirmImport", sender: vc)
                                        
                                    }
                                }
                            }
                            
                            
                        }))
                        
                        alert.addAction(UIAlertAction(title: "Legacy (BIP44, 1)", style: .default, handler: { action in
                            cv.addConnectingView(vc: vc, description: "importing...")
                            let bip44Dict = dict["bip44"] as! NSDictionary
                            
                            Import.importColdCard(coldcardDict: bip44Dict, fingerprint: fingerprint) { (walletToImport) in
                                
                                if walletToImport != nil {
                                    DispatchQueue.main.async { [unowned vc = self] in
                                        cv.removeConnectingView()
                                        vc.walletName = walletToImport!["name"] as! String
                                        vc.walletToImport = walletToImport!
                                        vc.performSegue(withIdentifier: "goConfirmImport", sender: vc)
                                        
                                    }
                                }
                            }
                            
                        }))
                        
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
                        alert.popoverPresentationController?.sourceView = vc.view
                        vc.present(alert, animated: true, completion: nil)
                        
                    }
                }
                
            } catch {
                /// It is not an Account Map.
                Import.importDescriptor(descriptor: descriptor) { [unowned vc = self] walletDict in
                    
                    if walletDict != nil {
                        DispatchQueue.main.async { [unowned vc = self] in
                            vc.walletToImport = walletDict!
                            vc.walletName = walletDict!["name"] as! String
                            vc.performSegue(withIdentifier: "goConfirmImport", sender: vc)
                            
                        }
                        
                    } else {
                        cv.removeConnectingView()
                        showAlert(vc: vc, title: "Error", message: "error importing that account")
                        
                    }
                }
            }
        }
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        let id = segue.identifier
        
        switch id {
            
        case "goConfirmImport":
            if let vc = segue.destination as? ConfirmRecoveryViewController {
                vc.walletNameHash = walletName
                vc.walletDict = walletToImport
            }
            
        case "goImport":
        
        if let vc = segue.destination as? ScannerViewController {
            
            vc.isImporting = true
            vc.onImportDoneBlock = { [unowned thisVc = self] descriptor in
                
                thisVc.processDescriptor(descriptor: descriptor)
                
            }
            
        }
            
        case "goToTools":
            
            if let vc = segue.destination as? WalletToolsViewController {
                
                vc.wallet = self.wallet
                
                vc.sweepDoneBlock = { [unowned thisVc = self] result in
                    
                    thisVc.fullRefresh = true
                    thisVc.refresh()
                    showAlert(vc: thisVc, title: "Wallet Sweeped! 🤩", message: "We are refreshing your balances now.")
                    
                }
                
                vc.refillDoneBlock = { [unowned thisVc = self] result in
                    
                    thisVc.fullRefresh = false
                    thisVc.refresh()
                    showAlert(vc: thisVc, title: "Success!", message: "Keypool refilled 🤩")
                    
                }
                
            }
            
        case "addWallet":
            
            if let vc = segue.destination as? ChooseWalletFormatViewController {
                
                vc.walletDoneBlock = { [unowned thisVc = self] result in
                    
                    showAlert(vc: thisVc, title: "Success!", message: "Wallet created successfully!")
                    thisVc.isLoading = true
                    thisVc.fullRefresh = false
                    thisVc.refresh()
                    
                }
                
                vc.recoverDoneBlock = { [unowned thisVc = self] result in
                    
                    DispatchQueue.main.async {
                        
                        thisVc.isLoading = true
                        thisVc.fullRefresh = true
                        thisVc.refresh()
                        
                        showAlert(vc: thisVc, title: "Success!", message: "Wallet recovered 🤩!\n\nYour node is now rescanning the blockchain, balances may not show until the rescan completes.")
                        
                    }
                    
                }
                
            }
            
        default:
            
            break
            
        }
        
    }
    
}
