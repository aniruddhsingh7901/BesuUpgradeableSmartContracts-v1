// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import "./Poseidon.sol";
import "../interfaces/IState.sol";
import "./ArrayUtils.sol";

/// @title A sparse merkle tree implementation, which keeps tree history.
// Note that this SMT implementation does not allow for duplicated roots in the history,
// which may be a critical restriction for some projects
library Smt {
    /**
     * @dev Max return array length for SMT root history requests
     */
    uint256 public constant SMT_ROOT_HISTORY_RETURN_LIMIT = 1000;

    /**
     * @dev Max depth hard cap for SMT
     * We can't use depth > 256 because of bits number limitation in the uint256 data type.
     */
    uint256 public constant MAX_DEPTH_HARD_CAP = 256;

    /**
     * @dev Enum of SMT node types
     */
    enum NodeType {
        EMPTY,
        LEAF,
        MIDDLE
    }

    /**
     * @dev Sparse Merkle Tree data
     * Note that we count the SMT depth starting from 0, which is the root level.
     *
     * For example, the following tree has a maxDepth = 2:
     *
     *     O      <- root level (depth = 0)
     *    / \
     *   O   O    <- depth = 1
     *  / \ / \
     * O  O O  O  <- depth = 2
     */
    struct SmtData {
        mapping(uint256 => Node) nodes;
        uint256[] rootHistory; // root[]
        mapping(uint256 => RootEntry[]) rootEntries; // root => RootEntry[]
        uint256 maxDepth;
        // This empty reserved space is put in place to allow future versions
        // of the SMT library to add new SmtData struct fields without shifting down
        // storage of upgradable contracts that use this struct as a state variable
        // (see https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#storage-gaps)
        uint256[49] __gap;
    }

    /**
     * @dev Struct of the node proof in the SMT
     */
    struct Proof {
        uint256 root;
        bool existence;
        uint256[] siblings;
        uint256 index;
        uint256 value;
        bool auxExistence;
        uint256 auxIndex;
        uint256 auxValue;
    }

    /**
     * @dev Struct for SMT root internal storage representation.
     * @param replacedByRoot A root, which replaced this root.
     * @param createdAtTimestamp A time, when the root was saved to blockchain.
     * @param createdAtBlock A number of block, when the root was saved to blockchain.
     */
    struct RootEntry {
        uint256 historyIndex;
        uint256 createdAtTimestamp;
        uint256 createdAtBlock;
    }

    /**
     * @dev Struct SMT node.
     * @param NodeType type of node.
     * @param childLeft left child of node.
     * @param childRight right child of node.
     * @param Index index of node.
     * @param Value value of node.
     */
    struct Node {
        NodeType nodeType;
        uint256 childLeft;
        uint256 childRight;
        uint256 index;
        uint256 value;
    }

    using BinarySearchSmtRoots for SmtData;
    using ArrayUtils for uint256[];

    /**
     * @dev Reverts if root does not exist in SMT roots history.
     * @param self SMT data.
     * @param root SMT root.
     */
    modifier onlyExistingRoot(SmtData storage self, uint256 root) {
        require(rootExists(self, root), "Root does not exist");
        _;
    }

    /**
     * @dev Add a node to the SMT
     * @param i Index of node
     * @param v Value of node
     */
    function add(SmtData storage self, uint256 i, uint256 v) external {
        Node memory node = Node({
            nodeType: NodeType.LEAF,
            childLeft: 0,
            childRight: 0,
            index: i,
            value: v
        });

        uint256 prevRoot = getRoot(self);
        uint256 newRoot = _addLeaf(self, node, prevRoot, 0);

        self.rootHistory.push(newRoot);

        self.rootEntries[newRoot].push(RootEntry({
            historyIndex: self.rootHistory.length - 1,
            createdAtTimestamp: block.timestamp,
            createdAtBlock: block.number
        }));
    }

    /**
     * @dev Get SMT root history length
     * @return SMT history length
     */
    function getRootHistoryLength(SmtData storage self) external view returns (uint256) {
        return self.rootHistory.length;
    }

    /**
     * @dev Get SMT root history
     * @param startIndex start index of history
     * @param length history length
     * @return array of RootInfo structs
     */
    function getRootHistory(
        SmtData storage self,
        uint256 startIndex,
        uint256 length
    ) external view returns (IState.RootInfo[] memory) {
        uint256[] memory history = self.rootHistory.sliceArrUint256(startIndex, length, SMT_ROOT_HISTORY_RETURN_LIMIT);
        IState.RootInfo[] memory result = new IState.RootInfo[](history.length);

        for (uint256 i = 0; i < history.length; i++) {
            result[i] = getRootInfo(self, history[i]);
        }
        return result;
    }

    /**
     * @dev Get the SMT node by hash
     * @param nodeHash Hash of a node
     * @return A node struct
     */
    function getNode(SmtData storage self, uint256 nodeHash) public view returns (Node memory) {
        return self.nodes[nodeHash];
    }

    /**
     * @dev Get the proof if a node with specific index exists or not exists in the SMT
     * @param index Node index
     * @return Proof struct
     */
    function getProof(SmtData storage self, uint256 index) external view returns (Proof memory) {
        return getProofByRoot(self, index, getRoot(self));
    }

    /**
     * @dev Get the proof if a node with specific index exists or not exists in the SMT for some historical tree state
     * @param index Node index
     * @param historicalRoot Historical SMT roof to get proof for
     * @return Proof struct
     */
    function getProofByRoot(
        SmtData storage self,
        uint256 index,
        uint256 historicalRoot
    ) public view onlyExistingRoot(self, historicalRoot) returns (Proof memory) {
        uint256[] memory siblings = new uint256[](self.maxDepth);
        // Solidity does not guarantee that memory vars are zeroed out
        for (uint256 i = 0; i < self.maxDepth; i++) {
            siblings[i] = 0;
        }

        Proof memory proof = Proof({
            root: historicalRoot,
            existence: false,
            siblings: siblings,
            index: index,
            value: 0,
            auxExistence: false,
            auxIndex: 0,
            auxValue: 0
        });

        uint256 nextNodeHash = historicalRoot;
        Node memory node;

        for (uint256 i = 0; i <= self.maxDepth; i++) {
            node = getNode(self, nextNodeHash);
            if (node.nodeType == NodeType.EMPTY) {
                break;
            } else if (node.nodeType == NodeType.LEAF) {
                if (node.index == proof.index) {
                    proof.existence = true;
                    proof.value = node.value;
                    break;
                } else {
                    proof.auxExistence = true;
                    proof.auxIndex = node.index;
                    proof.auxValue = node.value;
                    proof.value = node.value;
                    break;
                }
            } else if (node.nodeType == NodeType.MIDDLE) {
                if ((proof.index >> i) & 1 == 1) {
                    nextNodeHash = node.childRight;
                    proof.siblings[i] = node.childLeft;
                } else {
                    nextNodeHash = node.childLeft;
                    proof.siblings[i] = node.childRight;
                }
            } else {
                revert("Invalid node type");
            }
        }
        return proof;
    }

    /**
     * @dev Get the proof if a node with specific index exists or not exists in the SMT for some historical timestamp
     * @param index Node index
     * @param timestamp The nearest timestamp to get proof for
     * @return Proof struct
     */
    function getProofByTime(
        SmtData storage self,
        uint256 index,
        uint256 timestamp
    ) public view returns (Proof memory) {
        IState.RootInfo memory rootInfo = getRootInfoByTime(self, timestamp);

        require(rootInfo.root != 0, "historical root not found");

        return getProofByRoot(self, index, rootInfo.root);
    }

    /**
     * @dev Get the proof if a node with specific index exists or not exists in the SMT for some historical block number
     * @param index Node index
     * @param blockNumber The nearest block number to get proof for
     * @return Proof struct
     */
    function getProofByBlock(
        SmtData storage self,
        uint256 index,
        uint256 blockNumber
    ) external view returns (Proof memory) {
        IState.RootInfo memory rootInfo = getRootInfoByBlock(self, blockNumber);

        require(rootInfo.root != 0, "historical root not found");

        return getProofByRoot(self, index, rootInfo.root);
    }

    function getRoot(SmtData storage self) public view returns (uint256) {
        return self.rootHistory.length > 0 ? self.rootHistory[self.rootHistory.length - 1] : 0;
    }

    /**
     * @dev Binary search by timestamp
     * @param timestamp timestamp
     * return RootInfo struct
     */
    function getRootInfoByTime(
        SmtData storage self,
        uint256 timestamp
    ) public view returns (IState.RootInfo memory) {
        require(timestamp <= block.timestamp, "errNoFutureAllowed");

        uint256 root = self.binarySearchUint256(
            timestamp,
            BinarySearchSmtRoots.SearchType.TIMESTAMP
        );

        return getRootInfo(self, root);
    }

    /**
     * @dev Binary search by block number
     * @param blockN block number
     * return RootInfo struct
     */
    function getRootInfoByBlock(
        SmtData storage self,
        uint256 blockN
    ) public view returns (IState.RootInfo memory) {
        require(blockN <= block.number, "errNoFutureAllowed");

        uint256 root = self.binarySearchUint256(blockN, BinarySearchSmtRoots.SearchType.BLOCK);

        return getRootInfo(self, root);
    }

    /**
     * @dev Returns root info by root
     * @param root root
     * return RootInfo struct
     */
    function getRootInfo(
        SmtData storage self,
        uint256 root
    ) public view onlyExistingRoot(self, root) returns (IState.RootInfo memory) {
        RootEntry storage re = _getLatestRootEntryOfSameRoot(self, root);

        uint256 nextHistoryIndex = re.historyIndex + 1;
        bool isLastRoot = nextHistoryIndex == self.rootHistory.length;

        RootEntry memory nre = isLastRoot
            ? RootEntry({
                historyIndex: 0,
                createdAtTimestamp: 0,
                createdAtBlock: 0
              })
            : _getRootEntryByIndex(self, nextHistoryIndex);

        return
            IState.RootInfo({
                root: root,
                replacedByRoot: isLastRoot ? 0 : self.rootHistory[nextHistoryIndex],
                createdAtTimestamp: re.createdAtTimestamp,
                replacedAtTimestamp: nre.createdAtTimestamp,
                createdAtBlock: re.createdAtBlock,
                replacedAtBlock: nre.createdAtBlock
            });
    }

    /**
     * @dev Checks if root exists
     * @param root root
     * return true if root exists
     */
    function rootExists(SmtData storage self, uint256 root) public view returns (bool) {
        return self.rootEntries[root].length > 0;
    }

    /**
     * @dev Sets max depth of the SMT
     * @param maxDepth max depth
     */
    function setMaxDepth(SmtData storage self, uint256 maxDepth) external {
        require(maxDepth > 0, "Max depth must be greater than zero");
        require(maxDepth > self.maxDepth, "Max depth can only be increased");
        require(maxDepth <= MAX_DEPTH_HARD_CAP, "Max depth is greater than hard cap");
        self.maxDepth = maxDepth;
    }

    /**
     * @dev Gets max depth of the SMT
     * return max depth
     */
    function getMaxDepth(SmtData storage self) external view returns (uint256) {
        return self.maxDepth;
    }

    function _addLeaf(
        SmtData storage self,
        Node memory newLeaf,
        uint256 nodeHash,
        uint256 depth
    ) internal returns (uint256) {
        if (depth > self.maxDepth) {
            revert("Max depth reached");
        }

        Node memory node = self.nodes[nodeHash];
        uint256 nextNodeHash;
        uint256 leafHash = 0;

        if (node.nodeType == NodeType.EMPTY) {
            leafHash = _addNode(self, newLeaf);
        } else if (node.nodeType == NodeType.LEAF) {
            leafHash = node.index == newLeaf.index
                ? _addNode(self, newLeaf)
                : _pushLeaf(self, newLeaf, node, depth);
        } else if (node.nodeType == NodeType.MIDDLE) {
            Node memory newNodeMiddle;

            if ((newLeaf.index >> depth) & 1 == 1) {
                nextNodeHash = _addLeaf(self, newLeaf, node.childRight, depth + 1);

                newNodeMiddle = Node({
                    nodeType: NodeType.MIDDLE,
                    childLeft: node.childLeft,
                    childRight: nextNodeHash,
                    index: 0,
                    value: 0
                });
            } else {
                nextNodeHash = _addLeaf(self, newLeaf, node.childLeft, depth + 1);

                newNodeMiddle = Node({
                    nodeType: NodeType.MIDDLE,
                    childLeft: nextNodeHash,
                    childRight: node.childRight,
                    index: 0,
                    value: 0
                });
            }

            leafHash = _addNode(self, newNodeMiddle);
        }

        return leafHash;
    }

    function _pushLeaf(
        SmtData storage self,
        Node memory newLeaf,
        Node memory oldLeaf,
        uint256 depth
    ) internal returns (uint256) {
        // no reason to continue if we are at max possible depth
        // as, anyway, we exceed the depth going down the tree
        if (depth >= self.maxDepth) {
            revert("Max depth reached");
        }

        Node memory newNodeMiddle;
        bool newLeafBitAtDepth = (newLeaf.index >> depth) & 1 == 1;
        bool oldLeafBitAtDepth = (oldLeaf.index >> depth) & 1 == 1;

        // Check if we need to go deeper if diverge at the depth's bit
        if (newLeafBitAtDepth == oldLeafBitAtDepth) {
            uint256 nextNodeHash = _pushLeaf(self, newLeaf, oldLeaf, depth + 1);

            if (newLeafBitAtDepth) {
                // go right
                newNodeMiddle = Node(NodeType.MIDDLE, 0, nextNodeHash, 0, 0);
            } else {
                // go left
                newNodeMiddle = Node(NodeType.MIDDLE, nextNodeHash, 0, 0, 0);
            }
            return _addNode(self, newNodeMiddle);
        }

        if (newLeafBitAtDepth) {
            newNodeMiddle = Node({
                nodeType: NodeType.MIDDLE,
                childLeft: _getNodeHash(oldLeaf),
                childRight: _getNodeHash(newLeaf),
                index: 0,
                value: 0
            });
        } else {
            newNodeMiddle = Node({
                nodeType: NodeType.MIDDLE,
                childLeft: _getNodeHash(newLeaf),
                childRight: _getNodeHash(oldLeaf),
                index: 0,
                value: 0
            });
        }

        _addNode(self, newLeaf);
        return _addNode(self, newNodeMiddle);
    }

    function _addNode(SmtData storage self, Node memory node) internal returns (uint256) {
        uint256 nodeHash = _getNodeHash(node);
        require(
            self.nodes[nodeHash].nodeType == NodeType.EMPTY,
            "Node already exists with the same index and value"
        );
        // We do not store empty nodes so can check if an entry exists
        self.nodes[nodeHash] = node;
        return nodeHash;
    }

    function _getNodeHash(Node memory node) internal view returns (uint256) {
        uint256 nodeHash = 0;
        if (node.nodeType == NodeType.LEAF) {
            uint256[3] memory params = [node.index, node.value, uint256(1)];
            nodeHash = PoseidonUnit3L.poseidon(params);
        } else if (node.nodeType == NodeType.MIDDLE) {
            nodeHash = PoseidonUnit2L.poseidon([node.childLeft, node.childRight]);
        }
        return nodeHash; // Note: expected to return 0 if NodeType.EMPTY, which is the only option left
    }

    function _getLatestRootEntryOfSameRoot(SmtData storage self, uint256 root) internal view returns (RootEntry storage) {
        RootEntry[] storage res = self.rootEntries[root];
        return res[res.length - 1];
    }
}

/// @title A binary search for the sparse merkle tree root history
// Implemented as a separate library for testing purposes
library BinarySearchSmtRoots {
    /**
     * @dev Enum for the SMT history field selection
     */
    enum SearchType {
        TIMESTAMP,
        BLOCK
    }

    function binarySearchUint256(
        Smt.SmtData storage self,
        uint256 value,
        SearchType searchType
    ) internal view returns (uint256) {
        if (self.rootHistory.length == 0) {
            return 0;
        }

        uint256 min = 0;
        uint256 max = self.rootHistory.length - 1;
        uint256 mid;
        uint256 midRoot;

        while (min <= max) {
            mid = (max + min) / 2;
            midRoot = self.rootHistory[mid];

            uint256 midValue = fieldSelector(_getRootEntryByIndex(self, mid), searchType);
            if (midValue == value) {
                while (mid < self.rootHistory.length - 1) {
                    uint256 nextRoot = self.rootHistory[mid + 1];
                    uint256 nextValue = fieldSelector(_getRootEntryByIndex(self, mid + 1), searchType);
                    if (nextValue == value) {
                        mid++;
                        midRoot = nextRoot;
                    } else {
                        return midRoot;
                    }
                }
                return midRoot;
            } else if (value > midValue) {
                min = mid + 1;
            } else if (value < midValue && mid > 0) {
                // mid > 0 is to avoid underflow
                max = mid - 1;
            } else {
                // This means that value < midValue && mid == 0. So we return zero,
                // when search for a value less than the value in the first root
                return 0;
            }
        }

        // The case when the searched value does not exist and we should take the closest smaller value
        // Index in the "max" var points to the root with max value smaller than the searched value
        return self.rootHistory[max];
    }

    function fieldSelector(
        Smt.RootEntry memory rti,
        SearchType st
    ) internal pure returns (uint256) {
        if (st == SearchType.BLOCK) {
            return rti.createdAtBlock;
        } else if (st == SearchType.TIMESTAMP) {
            return rti.createdAtTimestamp;
        } else {
            revert("Invalid search type");
        }
    }
}

function _getRootEntryByIndex(Smt.SmtData storage self, uint256 index) view returns (Smt.RootEntry storage) {
    uint256 root = self.rootHistory[index];
    Smt.RootEntry[] storage res = self.rootEntries[root];

    // binary search in root entries of specific root
    uint256 min = 0;
    uint256 max = res.length - 1;
    while (min <= max) {
        uint256 mid = (max + min) / 2;
        if (res[mid].historyIndex == index) {
            return res[mid];
        } else if (res[mid].historyIndex < index) {
            min = mid + 1;
        } else {
            max = mid - 1;
        }
    }
    revert("Root entry not found");
}
