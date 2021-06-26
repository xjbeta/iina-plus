function sendWup(t, e, i) {
    var r = new Taf.Wup;
    r.setServant(t),
    r.setFunc(e),
    r.writeStruct("tReq", i);
    var n = new HUYA.WebSocketCommand;
    n.iCmdType = HUYA.EWebSocketCommandType.EWSCmd_WupReq,
    n.vData = r.encode();
    var o = new Taf.JceOutputStream;
    n.writeTo(o);
    return o.getBuffer();
};

function sendRegister(t) {
    var e = new Taf.JceOutputStream;
    t.writeTo(e);
    var i = new HUYA.WebSocketCommand;
    i.iCmdType = HUYA.EWebSocketCommandType.EWSCmd_RegisterReq;
    i.vData = e.getBinBuffer();
    e = new Taf.JceOutputStream;
    i.writeTo(e);
    return e.getBuffer();
};

function sendRegisterGroups(arr) {
    var data = new HUYA.WSRegisterGroupReq;
    data.vGroupId.value = arr;
    var os = new Taf.JceOutputStream;
    data.writeTo(os);
    var req = new HUYA.WebSocketCommand;
    req.iCmdType = HUYA.EWebSocketCommandType.EWSCmdC2S_RegisterGroupReq;
    req.vData = os.getBinBuffer();
    os = new Taf.JceOutputStream;
    req.writeTo(os);
    return os.getBuffer();
};

function test(t) {
    var arrayBuffer = new Uint8Array(t).buffer;
    var i = new Taf.JceInputStream(arrayBuffer);
    var n = new HUYA.WebSocketCommand;

    switch (n.readFrom(i), n.iCmdType) {
        case HUYA.EWebSocketCommandType.EWSCmd_RegisterRsp:
            return 'EWebSocketCommandType.EWSCmd_RegisterRsp';
        case HUYA.EWebSocketCommandType.EWSCmdS2C_RegisterGroupRsp:
            return 'EWebSocketCommandType.EWSCmdS2C_RegisterGroupRsp';
        case HUYA.EWebSocketCommandType.EWSCmdS2C_UnRegisterGroupRsp:
            return 'EWebSocketCommandType.EWSCmdS2C_UnRegisterGroupRsp';
        case HUYA.EWebSocketCommandType.EWSCmd_WupRsp:
            return 'EWebSocketCommandType.EWSCmd_WupRsp';
        case HUYA.EWebSocketCommandType.EWSCmdS2C_MsgPushReq:
            i = new Taf.JceInputStream(n.vData.buffer),
            (U = new HUYA.WSPushMessage).readFrom(i);
            var R = U.iUri,
                b = U.lMsgId;
            
            
            if (R !== 1400)
                return;
            
            i = new Taf.JceInputStream(U.sMsg.buffer);

            
            var messageNotice = new DM.MessageNotice();
            
            messageNotice.readFrom(i);
            
            return messageNotice.sContent;
        case HUYA.EWebSocketCommandType.EWSCmdS2C_HeartBeatAck:
            return 'EWebSocketCommandType.EWSCmdS2C_HeartBeatAck';
        case HUYA.EWebSocketCommandType.EWSCmdS2C_VerifyCookieRsp:
            return 'EWebSocketCommandType.EWSCmdS2C_VerifyCookieRsp';
        case HUYA.EWebSocketCommandType.EWSCmdS2C_MsgPushReq_V2:
            return 'EWebSocketCommandType.EWSCmdS2C_MsgPushReq_V2';
            var U;
            i = new p.JceInputStream(n.vData.buffer),
            (U = new HUYA.WSPushMessage_V2).readFrom(i);
            for (var k = 0, L = HUYA.vMsgItem.value.length; k < L; k++) {
                var N;
                R = (N = HUYA.vMsgItem.value[k]).iUri,
                b = N.lMsgId;
                if (e.danmuLruCache)
                    if (d.cache(b)) {
                        a.log("重复的消息id", b, HUYA.sGroupId);
                        continue
                    }
                if (!e.dropDanmuOpen || !e.isFilterDanmu() || 1400 != R && 6298 != R) {
                    var M;
                    P = l.UriMapping[R],
                    i = new p.JceInputStream(N.sMsg);
                    if (A(R, "", N.sMsg.buffer), P)
                        (M = new P).readFrom(i),
                        G(M),
                        y && !l.NoLog[R.toString()] && a.log("%c<<<<<<< %crspMsgPushV2, %curi=" + R, D("#0000E3"), D("black"), D("#8600FF"), M),
                        f.dispatch(R, M);
                    else
                        v && a.info("收到未映射的 WSPushMessage_V2 uri=" + R)
                } else
                    e.dropDanmuCount++
            }
            break;
        case HUYA.EWebSocketCommandType.EWSCmdS2C_EnterP2PAck:
            return 'EWebSocketCommandType.EWSCmdS2C_EnterP2PAck';
        case HUYA.EWebSocketCommandType.EWSCmdS2C_ExitP2PAck:
            return 'EWebSocketCommandType.EWSCmdS2C_ExitP2PAck';
        default:
            return 'EWebSocketCommandType.Default';
    };
};


var Taf = Taf || {};
Taf.INT8 = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt8(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt8(tag, true, def)
    };
    this._className = function() {
        return Taf.CHAR
    }
};
Taf.INT16 = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt16(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt16(tag, true, def)
    };
    this._className = function() {
        return Taf.SHORT
    }
};
Taf.INT32 = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt32(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt32(tag, true, def)
    };
    this._className = function() {
        return Taf.INT32
    }
};
Taf.INT64 = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt64(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt64(tag, true, def)
    };
    this._className = function() {
        return Taf.INT64
    }
};
Taf.UINT8 = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt16(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt16(tag, true, def)
    };
    this._className = function() {
        return Taf.SHORT
    }
};
Taf.UInt16 = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt32(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt32(tag, true, def)
    };
    this._className = function() {
        return Taf.INT32
    }
};
Taf.UInt32 = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt64(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt64(tag, true, def)
    };
    this._className = function() {
        return Taf.INT64
    }
};
Taf.Float = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeFloat(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readFloat(tag, true, def)
    };
    this._className = function() {
        return Taf.FLOAT
    }
};
Taf.Double = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeDouble(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readDouble(tag, true, def)
    };
    this._className = function() {
        return Taf.DOUBLE
    }
};
Taf.STRING = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeString(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readString(tag, true, def)
    };
    this._className = function() {
        return Taf.STRING
    }
};
Taf.BOOLEAN = function() {
    this._clone = function() {
        return false
    };
    this._write = function(os, tag, val) {
        return os.writeBoolean(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readBoolean(tag, true, def)
    };
    this._className = function() {
        return Taf.BOOLEAN
    }
};
Taf.ENUM = function() {
    this._clone = function() {
        return 0
    };
    this._write = function(os, tag, val) {
        return os.writeInt32(tag, val)
    };
    this._read = function(is, tag, def) {
        return is.readInt32(tag, true, def)
    }
};
Taf.Vector = function(proto) {
    this.proto = proto;
    this.value = new Array
};
Taf.Vector.prototype._clone = function() {
    return new Taf.Vector(this.proto)
};
Taf.Vector.prototype._write = function(os, tag, val) {
    return os.writeVector(tag, val)
};
Taf.Vector.prototype._read = function(is, tag, def) {
    return is.readVector(tag, true, def)
};
Taf.Vector.prototype._className = function() {
    return Taf.TypeHelp.VECTOR.replace("$t", this.proto._className())
};
Taf.Map = function(kproto, vproto) {
    this.kproto = kproto;
    this.vproto = vproto;
    this.value = new Object
};
Taf.Map.prototype._clone = function() {
    return new Taf.Map(this.kproto, this.vproto)
};
Taf.Map.prototype._write = function(os, tag, val) {
    return os.writeMap(tag, val)
};
Taf.Map.prototype._read = function(is, tag, def) {
    return is.readMap(tag, true, def)
};
Taf.Map.prototype.put = function(key, value) {
    this.value[key] = value
};
Taf.Map.prototype.get = function(key) {
    return this.value[key]
};
Taf.Map.prototype.remove = function(key) {
    delete this.value[key]
};
Taf.Map.prototype.clear = function() {
    this.value = new Object
};
Taf.Map.prototype.size = function() {
    var anum = 0;
    for (var key in this.value) {
        anum++
    }
    return anum
};
Taf.Map.prototype._className = function() {
    return Taf.TypeHelp.Map.replace("$k", this.kproto._className()).replace("$v", this.vproto._className())
};
Taf.DataHelp = {
    EN_INT8: 0,
    EN_INT16: 1,
    EN_INT32: 2,
    EN_INT64: 3,
    EN_FLOAT: 4,
    EN_DOUBLE: 5,
    EN_STRING1: 6,
    EN_STRING4: 7,
    EN_MAP: 8,
    EN_LIST: 9,
    EN_STRUCTBEGIN: 10,
    EN_STRUCTEND: 11,
    EN_ZERO: 12,
    EN_SIMPLELIST: 13
};
Taf.TypeHelp = {
    BOOLEAN: "bool",
    CHAR: "char",
    SHORT: "short",
    INT32: "int32",
    INT64: "int64",
    FLOAT: "float",
    DOUBLE: "double",
    STRING: "string",
    VECTOR: "list<$t>",
    MAP: "map<$k, $v>"
};
Taf.BinBuffer = function(buffer) {
    this.buf = null;
    this.vew = null;
    this.len = 0;
    this.position = 0;
    if (buffer != null && buffer != undefined && buffer instanceof Taf.BinBuffer) {
        this.buf = buffer.buf;
        this.vew = new DataView(this.buf);
        this.len = buffer.length;
        this.position = buffer.position
    }
    if (buffer != null && buffer != undefined && buffer instanceof ArrayBuffer) {
        this.buf = buffer;
        this.vew = new DataView(this.buf);
        this.len = this.vew.byteLength;
        this.position = 0
    }
    this.__defineGetter__("length", function() {
        return this.len
    });
    this.__defineGetter__("buffer", function() {
        return this.buf
    })
};
Taf.BinBuffer.prototype._write = function(os, tag, val) {
    return os.writeBytes(tag, val)
};
Taf.BinBuffer.prototype._read = function(os, tag, def) {
    return os.readBytes(tag, true, def)
};
Taf.BinBuffer.prototype._clone = function() {
    return new Taf.BinBuffer
};
Taf.BinBuffer.prototype.allocate = function(uiLength) {
    uiLength = this.position + uiLength;
    if (this.buf != null && this.buf.length > uiLength) {
        return
    }
    var temp = new ArrayBuffer(Math.max(256, uiLength * 2));
    if (this.buf != null) {
        new Uint8Array(temp).set(new Uint8Array(this.buf));
        this.buf = undefined
    }
    this.buf = temp;
    this.vew = undefined;
    this.vew = new DataView(this.buf)
};
Taf.BinBuffer.prototype.getBuffer = function() {
    var temp = new ArrayBuffer(this.len);
    new Uint8Array(temp).set(new Uint8Array(this.buf, 0, this.len));
    return temp
};
Taf.BinBuffer.prototype.memset = function(fbuf, offset, length) {
    this.allocate(length);
    new Uint8Array(this.buf).set(new Uint8Array(fbuf, offset, length), this.position)
};
Taf.BinBuffer.prototype.writeInt8 = function(value) {
    this.allocate(1);
    this.vew.setInt8(this.position, value);
    this.position += 1;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeUInt8 = function(value) {
    this.allocate(1);
    this.vew.setUint8(this.position++, value);
    this.len = this.position
};
Taf.BinBuffer.prototype.writeInt16 = function(value) {
    this.allocate(2);
    this.vew.setInt16(this.position, value);
    this.position += 2;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeUInt16 = function(value) {
    this.allocate(2);
    this.vew.setUint16(this.position, value);
    this.position += 2;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeInt32 = function(value) {
    this.allocate(4);
    this.vew.setInt32(this.position, value);
    this.position += 4;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeUInt32 = function(value) {
    this.allocate(4);
    this.vew.setUint32(this.position, value);
    this.position += 4;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeInt64 = function(value) {
    if (typeof value == "string") {
        this.allocate(8);
        value = value.toLowerCase();
        var div = 4294967296;
        var low = 0;
        var hight = 0;
        for (var i = 0; i < value.length; i++) {
            var num = value.charCodeAt(i) - 48;
            if (num > 9) {
                num = num - 39
            }
            low = low * 10 + num;
            var dd = Math.floor(low / div);
            hight = hight * 10 + dd;
            low = low % div
        }
        this.vew.setUint32(this.position, hight);
        this.vew.setUint32(this.position + 4, low);
        this.position += 8;
        this.len = this.position;
        return
    }
    this.allocate(8);
    this.vew.setUint32(this.position, parseInt(value / 4294967296));
    this.vew.setUint32(this.position + 4, value % 4294967296);
    this.position += 8;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeFloat = function(value) {
    this.allocate(4);
    this.vew.setFloat32(this.position, value);
    this.position += 4;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeDouble = function(value) {
    this.allocate(8);
    this.vew.setFloat64(this.position, value);
    this.position += 8;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeString = function(value) {
    for (var arr = [], i = 0; i < value.length; i++) {
        arr.push(value.charCodeAt(i) & 255)
    }
    this.allocate(arr.length);
    new Uint8Array(this.buf).set(new Uint8Array(arr), this.position);
    this.position += arr.length;
    this.len = this.position
};
Taf.BinBuffer.prototype.writeBytes = function(value) {
    if (value.length == 0 || value.buf == null)
        return;
    this.allocate(value.length);
    new Uint8Array(this.buf).set(new Uint8Array(value.buf, 0, value.length), this.position);
    this.position += value.length;
    this.len = this.position
};
Taf.BinBuffer.prototype.readInt8 = function() {
    return this.vew.getInt8(this.position++)
};
Taf.BinBuffer.prototype.readInt16 = function() {
    this.position += 2;
    return this.vew.getInt16(this.position - 2)
};
Taf.BinBuffer.prototype.readInt32 = function() {
    this.position += 4;
    return this.vew.getInt32(this.position - 4)
};
Taf.BinBuffer.prototype.readUInt8 = function() {
    this.position += 1;
    return this.vew.getUint8(this.position - 1)
};
Taf.BinBuffer.prototype.readUInt16 = function() {
    this.position += 2;
    return this.vew.getUint16(this.position - 2)
};
Taf.BinBuffer.prototype.readUInt32 = function() {
    this.position += 4;
    return this.vew.getUint32(this.position - 4)
};
Taf.BinBuffer.prototype.readInt64 = function() {
    var H4 = this.vew.getUint32(this.position);
    var L4 = this.vew.getUint32(this.position + 4);
    this.position += 8;
    var result = "";
    var highRemain,
        lowRemain,
        tempNum;
    var MaxLowUint = Math.pow(2, 32);
    var radix = 10;
    while (H4 != 0 || L4 != 0) {
        highRemain = H4 % radix;
        tempNum = highRemain * MaxLowUint + L4;
        lowRemain = tempNum % radix;
        result = lowRemain.toString(radix) + result;
        H4 = (H4 - highRemain) / radix;
        L4 = (tempNum - lowRemain) / radix
    }
    return result
};
Taf.BinBuffer.prototype.readFloat = function() {
    var temp = this.vew.getFloat32(this.position);
    this.position += 4;
    return temp
};
Taf.BinBuffer.prototype.readDouble = function() {
    var temp = this.vew.getFloat64(this.position);
    this.position += 8;
    return temp
};
Taf.BinBuffer.prototype.readString = function(value) {
    for (var arr = [], i = 0; i < value; i++) {
        arr.push(String.fromCharCode(this.vew.getUint8(this.position++)))
    }
    var result = arr.join("");
    try {
        result = decodeURIComponent(escape(result))
    } catch (e) {}
    result = result.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\'/g, "&#39;").replace(/\"/g, "&quot;");
    return result
};
Taf.BinBuffer.prototype.readBytes = function(value) {
    var temp = new Taf.BinBuffer;
    temp.allocate(value);
    temp.memset(this.buf, this.position, value);
    temp.position = 0;
    temp.len = value;
    this.position = this.position + value;
    return temp
};
Taf.JceOutputStream = function() {
    this.buf = new Taf.BinBuffer;
    this.getBinBuffer = function() {
        return this.buf
    };
    this.getBuffer = function() {
        return this.buf.getBuffer()
    }
};
Taf.JceOutputStream.prototype.clear = function() {
    this.buf = new Taf.BinBuffer;
    return this
};
Taf.JceOutputStream.prototype.writeTo = function(tag, type) {
    if (tag < 15) {
        this.buf.writeUInt8(tag << 4 & 240 | type)
    } else {
        this.buf.writeUInt16((240 | type) << 8 | tag)
    }
};
Taf.JceOutputStream.prototype.writeBoolean = function(tag, value) {
    this.writeInt8(tag, value == true ? 1 : 0)
};
Taf.JceOutputStream.prototype.writeInt8 = function(tag, value) {
    if (value == 0) {
        this.writeTo(tag, Taf.DataHelp.EN_ZERO)
    } else {
        this.writeTo(tag, Taf.DataHelp.EN_INT8);
        this.buf.writeInt8(value)
    }
};
Taf.JceOutputStream.prototype.writeInt16 = function(tag, value) {
    if (value >= -128 && value <= 127) {
        this.writeInt8(tag, value)
    } else {
        this.writeTo(tag, Taf.DataHelp.EN_INT16);
        this.buf.writeInt16(value)
    }
};
Taf.JceOutputStream.prototype.writeInt32 = function(tag, value) {
    if (value >= -32768 && value <= 32767) {
        this.writeInt16(tag, value)
    } else {
        this.writeTo(tag, Taf.DataHelp.EN_INT32);
        this.buf.writeInt32(value)
    }
};
Taf.JceOutputStream.prototype.writeInt64 = function(tag, value) {
    if (value >= -2147483648 && value <= 2147483647) {
        this.writeInt32(tag, value)
    } else {
        this.writeTo(tag, Taf.DataHelp.EN_INT64);
        this.buf.writeInt64(value)
    }
};
Taf.JceOutputStream.prototype.writeUInt8 = function(tag, value) {
    this.writeInt16(tag, value)
};
Taf.JceOutputStream.prototype.writeUInt16 = function(tag, value) {
    this.writeInt32(tag, value)
};
Taf.JceOutputStream.prototype.writeUInt32 = function(tag, value) {
    this.writeInt64(tag, value)
};
Taf.JceOutputStream.prototype.writeFloat = function(tag, value) {
    if (value == 0) {
        this.writeTo(tag, Taf.DataHelp.EN_ZERO)
    } else {
        this.writeTo(tag, Taf.DataHelp.EN_FLOAT);
        this.buf.writeFloat(value)
    }
};
Taf.JceOutputStream.prototype.writeDouble = function(tag, value) {
    if (value == 0) {
        this.writeTo(tag, Taf.DataHelp.EN_ZERO)
    } else {
        this.writeTo(tag, Taf.DataHelp.EN_DOUBLE);
        this.buf.writeDouble(value)
    }
};
Taf.JceOutputStream.prototype.writeStruct = function(tag, value) {
    if (value.writeTo == undefined) {
        throw Error("not defined writeTo Function")
    }
    this.writeTo(tag, Taf.DataHelp.EN_STRUCTBEGIN);
    value.writeTo(this);
    this.writeTo(0, Taf.DataHelp.EN_STRUCTEND)
};
Taf.JceOutputStream.prototype.writeString = function(tag, value) {
    var str = value;
    try {
        str = unescape(encodeURIComponent(str))
    } catch (e) {}
    if (str.length > 255) {
        this.writeTo(tag, Taf.DataHelp.EN_STRING4);
        this.buf.writeUInt32(str.length)
    } else {
        this.writeTo(tag, Taf.DataHelp.EN_STRING1);
        this.buf.writeUInt8(str.length)
    }
    this.buf.writeString(str)
};
Taf.JceOutputStream.prototype.writeBytes = function(tag, value) {
    if (!(value instanceof Taf.BinBuffer)) {
        throw Error("value not instanceof Taf.BinBuffer")
    }
    this.writeTo(tag, Taf.DataHelp.EN_SIMPLELIST);
    this.writeTo(0, Taf.DataHelp.EN_INT8);
    this.writeInt32(0, value.length);
    this.buf.writeBytes(value)
};
Taf.JceOutputStream.prototype.writeVector = function(tag, value) {
    this.writeTo(tag, Taf.DataHelp.EN_LIST);
    this.writeInt32(0, value.value.length);
    for (var i = 0; i < value.value.length; i++) {
        value.proto._write(this, 0, value.value[i])
    }
};
Taf.JceOutputStream.prototype.writeMap = function(tag, value) {
    this.writeTo(tag, Taf.DataHelp.EN_MAP);
    this.writeInt32(0, value.size());
    for (var temp in value.value) {
        value.kproto._write(this, 0, temp);
        value.vproto._write(this, 1, value.value[temp])
    }
};
Taf.JceInputStream = function(buffer) {
    this.buf = new Taf.BinBuffer(buffer)
};
Taf.JceInputStream.prototype.setBuffer = function(arrayBuffer) {
    this.buf = new Taf.BinBuffer(arrayBuffer);
    return this
};
Taf.JceInputStream.prototype.readFrom = function() {
    var temp = this.buf.readUInt8();
    var tag = (temp & 240) >> 4;
    var type = temp & 15;
    if (tag >= 15)
        tag = this.buf.readUInt8();
    return {
        tag: tag,
        type: type
    }
};
Taf.JceInputStream.prototype.peekFrom = function() {
    var pos = this.buf.position;
    var head = this.readFrom();
    this.buf.position = pos;
    return {
        tag: head.tag,
        type: head.type,
        size: head.tag >= 15 ? 2 : 1
    }
};
Taf.JceInputStream.prototype.skipField = function(type) {
    switch (type) {
    case Taf.DataHelp.EN_INT8:
        this.buf.position += 1;
        break;
    case Taf.DataHelp.EN_INT16:
        this.buf.position += 2;
        break;
    case Taf.DataHelp.EN_INT32:
        this.buf.position += 4;
        break;
    case Taf.DataHelp.EN_INT64:
        this.buf.position += 8;
        break;
    case Taf.DataHelp.EN_STRING1:
        var a = this.buf.readUInt8();
        this.buf.position += a;
        break;
    case Taf.DataHelp.EN_STRING4:
        var b = this.buf.readInt32();
        this.buf.position += b;
        break;
    case Taf.DataHelp.EN_STRUCTBEGIN:
        this.skipToStructEnd();
        break;
    case Taf.DataHelp.EN_STRUCTEND:
    case Taf.DataHelp.EN_ZERO:
        break;
    case Taf.DataHelp.EN_MAP:
        {
            var size = this.readInt32(0, true);
            for (var i = 0; i < size * 2; ++i) {
                var head = this.readFrom();
                this.skipField(head.type)
            }
            break
        }case Taf.DataHelp.EN_SIMPLELIST:
        {
            var head = this.readFrom();
            if (head.type != Taf.DataHelp.EN_INT8) {
                throw Error("skipField with invalid type, type value: " + type + "," + head.type)
            }
            var a = this.readInt32(0, true);
            this.buf.position += a;
            break
        }case Taf.DataHelp.EN_LIST:
        {
            var size = this.readInt32(0, true);
            for (var i = 0; i < size; ++i) {
                var head = this.readFrom();
                this.skipField(head.type)
            }
            break
        }default:
        throw new Error("skipField with invalid type, type value: " + type)
    }
};
Taf.JceInputStream.prototype.skipToStructEnd = function() {
    for (;;) {
        var head = this.readFrom();
        this.skipField(head.type);
        if (head.type == Taf.DataHelp.EN_STRUCTEND) {
            return
        }
    }
};
Taf.JceInputStream.prototype.skipToTag = function(tag, require) {
    while (this.buf.position < this.buf.length) {
        var head = this.peekFrom();
        if (tag <= head.tag || head.type == Taf.DataHelp.EN_STRUCTEND) {
            return head.type == Taf.DataHelp.EN_STRUCTEND ? false : tag == head.tag
        }
        this.buf.position += head.size;
        this.skipField(head.type)
    }
    if (require)
        throw Error("require field not exist, tag:" + tag);
    return false
};
Taf.JceInputStream.prototype.readBoolean = function(tag, require, def) {
    return this.readInt8(tag, require, def) == 1 ? true : false
};
Taf.JceInputStream.prototype.readInt8 = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    switch (head.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8()
    }
    throw Error("read int8 type mismatch, tag:" + tag + ", get type:" + head.type)
};
Taf.JceInputStream.prototype.readInt16 = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    switch (head.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8();
    case Taf.DataHelp.EN_INT16:
        return this.buf.readInt16()
    }
    throw Error("read int16 type mismatch, tag:" + tag + ", get type:" + head.type)
};
Taf.JceInputStream.prototype.readInt32 = function(tag, requrire, def) {
    if (this.skipToTag(tag, requrire) == false) {
        return def
    }
    var head = this.readFrom();
    switch (head.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8();
    case Taf.DataHelp.EN_INT16:
        return this.buf.readInt16();
    case Taf.DataHelp.EN_INT32:
        return this.buf.readInt32()
    }
    throw Error("read int32 type mismatch, tag:" + tag + ", get type:" + head.type)
};
Taf.JceInputStream.prototype.readInt64 = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    switch (head.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8();
    case Taf.DataHelp.EN_INT16:
        return this.buf.readInt16();
    case Taf.DataHelp.EN_INT32:
        return this.buf.readInt32();
    case Taf.DataHelp.EN_INT64:
        return this.buf.readInt64()
    }
    throw Error("read int64 type mismatch, tag:" + tag + ", get type:" + head.type)
};
Taf.JceInputStream.prototype.readFloat = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    switch (head.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_FLOAT:
        return this.buf.readFloat()
    }
    throw Error("read float type mismatch, tag:" + tag + ", get type:" + h.type)
};
Taf.JceInputStream.prototype.readDouble = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    switch (head.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_DOUBLE:
        return this.buf.readDouble()
    }
    throw Error("read double type mismatch, tag:" + tag + ", get type:" + h.type)
};
Taf.JceInputStream.prototype.readUInt8 = function(tag, require, def) {
    return this.readInt16(tag, require, def)
};
Taf.JceInputStream.prototype.readUInt16 = function(tag, require, def) {
    return this.readInt32(tag, require, def)
};
Taf.JceInputStream.prototype.readUInt32 = function(tag, require, def) {
    return this.readInt64(tag, require, def)
};
Taf.JceInputStream.prototype.readStruct = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    if (head.type != Taf.DataHelp.EN_STRUCTBEGIN) {
        throw Error("read struct type mismatch, tag: " + tag + ", get type:" + head.type)
    }
    def.readFrom(this);
    this.skipToStructEnd();
    return def
};
Taf.JceInputStream.prototype.readString = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    if (head.type == Taf.DataHelp.EN_STRING1) {
        return this.buf.readString(this.buf.readUInt8())
    }
    if (head.type == Taf.DataHelp.EN_STRING4) {
        return this.buf.readString(this.buf.readUInt32())
    }
    throw Error("read 'string' type mismatch, tag: " + tag + ", get type: " + head.type + ".")
};
Taf.JceInputStream.prototype.readString2 = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    if (head.type == Taf.DataHelp.EN_STRING1) {
        return this.buf.readBytes(this.buf.readUInt8())
    }
    if (head.type == Taf.DataHelp.EN_STRING4) {
        return this.buf.readBytes(this.buf.readUInt32())
    }
    throw Error("read 'string2' type mismatch, tag: " + tag + ", get type: " + head.type + ".")
};
Taf.JceInputStream.prototype.readBytes = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    if (head.type == Taf.DataHelp.EN_SIMPLELIST) {
        var temp = this.readFrom();
        if (temp.type != Taf.DataHelp.EN_INT8) {
            throw Error("type mismatch, tag:" + tag + ",type:" + head.type + "," + temp.type)
        }
        var size = this.readInt32(0, true);
        if (size < 0) {
            throw Error("invalid size, tag:" + tag + ",type:" + head.type + "," + temp.type)
        }
        return this.buf.readBytes(size)
    }
    if (head.type == Taf.DataHelp.EN_LIST) {
        var size = this.readInt32(0, true);
        return this.buf.readBytes(size)
    }
    throw Error("type mismatch, tag:" + tag + ",type:" + head.type)
};
Taf.JceInputStream.prototype.readVector = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    if (head.type != Taf.DataHelp.EN_LIST) {
        throw Error("read 'vector' type mismatch, tag: " + tag + ", get type: " + head.type)
    }
    var size = this.readInt32(0, true);
    if (size < 0) {
        throw Error("invalid size, tag: " + tag + ", type: " + head.type + ", size: " + size)
    }
    for (var i = 0; i < size; ++i) {
        def.value.push(def.proto._read(this, 0, def.proto._clone()))
    }
    return def
};
Taf.JceInputStream.prototype.readMap = function(tag, require, def) {
    if (this.skipToTag(tag, require) == false) {
        return def
    }
    var head = this.readFrom();
    if (head.type != Taf.DataHelp.EN_MAP) {
        throw Error("read 'map' type mismatch, tag: " + tag + ", get type: " + head.type)
    }
    var size = this.readInt32(0, true);
    if (size < 0) {
        throw Error("invalid map, tag: " + tag + ", size: " + size)
    }
    for (var i = 0; i < size; i++) {
        var key = def.kproto._read(this, 0, def.kproto._clone());
        var val = def.vproto._read(this, 1, def.vproto._clone());
        def.put(key, val)
    }
    return def
};
Taf.Wup = function() {
    this.iVersion = 3;
    this.cPacketType = 0;
    this.iMessageType = 0;
    this.iRequestId = 0;
    this.sServantName = "";
    this.sFuncName = "";
    this.sBuffer = new Taf.BinBuffer;
    this.iTimeout = 0;
    this.context = new Taf.Map(new Taf.STRING, new Taf.STRING);
    this.status = new Taf.Map(new Taf.STRING, new Taf.STRING);
    this.newdata = new Taf.Map(new Taf.STRING, new Taf.BinBuffer);
    this.iStream = new Taf.JceInputStream;
    this.oStream = new Taf.JceOutputStream
};
Taf.Wup.prototype.hasKey = function(value) {
    return this.newdata.hasKey(value)
};
Taf.Wup.prototype.setVersion = function(value) {
    this.iVersion = value
};
Taf.Wup.prototype.getVersion = function(value) {
    return this.iVersion
};
Taf.Wup.prototype.setServant = function(value) {
    this.sServantName = value
};
Taf.Wup.prototype.setFunc = function(value) {
    this.sFuncName = value
};
Taf.Wup.prototype.setRequestId = function(value) {
    this.iRequestId = value ? value : ++this.iRequestId
};
Taf.Wup.prototype.getRequestId = function() {
    return this.iRequestId
};
Taf.Wup.prototype.setTimeOut = function(value) {
    this.iTimeout = value
};
Taf.Wup.prototype.getTimeOut = function() {
    return this.iTimeout
};
Taf.Wup.prototype.writeTo = function() {
    var os = this.oStream.clear();
    os.writeInt16(1, this.iVersion);
    os.writeInt8(2, this.cPacketType);
    os.writeInt32(3, this.iMessageType);
    os.writeInt32(4, this.iRequestId);
    os.writeString(5, this.sServantName);
    os.writeString(6, this.sFuncName);
    os.writeBytes(7, this.sBuffer);
    os.writeInt32(8, this.iTimeout);
    os.writeMap(9, this.context);
    os.writeMap(10, this.status);
    return new Taf.BinBuffer(os.getBuffer())
};
Taf.Wup.prototype.encode = function() {
    var os = this.oStream.clear();
    os.writeMap(0, this.newdata);
    this.sBuffer = os.getBinBuffer();
    var temp = this.writeTo();
    var buf = new Taf.BinBuffer;
    buf.writeInt32(4 + temp.len);
    buf.writeBytes(temp);
    return buf
};
Taf.Wup.prototype.writeBoolean = function(name, value) {
    var os = this.oStream.clear();
    os.writeBoolean(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeInt8 = function(name, value) {
    var os = this.oStream.clear();
    os.writeInt8(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeInt16 = function(name, value) {
    var os = this.oStream.clear();
    os.writeInt16(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeInt32 = function(name, value) {
    var os = this.oStream.clear();
    os.writeInt32(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeInt64 = function(name, value) {
    var os = this.oStream.clear();
    os.writeInt64(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeFloat = function(name, value) {
    var os = this.oStream.clear();
    os.writeFloat(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeDouble = function(name, value) {
    var os = this.oStream.clear();
    os.writeDouble(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeString = function(name, value) {
    var os = this.oStream.clear();
    os.writeString(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeVector = function(name, value) {
    var os = this.oStream.clear();
    os.writeVector(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBinBuffer()))
};
Taf.Wup.prototype.writeStruct = function(name, value) {
    var os = this.oStream.clear();
    os.writeStruct(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeBytes = function(name, value) {
    var os = this.oStream.clear();
    os.writeBytes(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.writeMap = function(name, value) {
    var os = this.oStream.clear();
    os.writeMap(0, value);
    this.newdata.put(name, new Taf.BinBuffer(os.getBuffer()))
};
Taf.Wup.prototype.readFrom = function(is) {
    this.iVersion = is.readInt16(1, true);
    this.cPacketType = is.readInt8(2, true);
    this.iMessageType = is.readInt32(3, true);
    this.iRequestId = is.readInt32(4, true);
    this.sServantName = is.readString(5, true);
    this.sFuncName = is.readString(6, true);
    if (localStorage.__wup) {
        logger.info("%c@@@ " + this.sServantName + "." + this.sFuncName, "color:white;background:black;", this)
    }
    this.sBuffer = is.readBytes(7, true);
    this.iTimeout = is.readInt32(8, true);
    this.context = is.readMap(9, true, this.context);
    this.status = is.readMap(10, true, this.status)
};
Taf.Wup.prototype.decode = function(buf) {
    var is = this.iStream.setBuffer(buf);
    var len = is.buf.vew.getInt32(is.buf.position);
    if (len < 4) {
        throw Error("packet length too short")
    }
    is.buf.position += 4;
    this.readFrom(is);
    is = this.iStream.setBuffer(this.sBuffer.getBuffer());
    this.newdata.clear();
    is.readMap(0, true, this.newdata)
};
Taf.Wup.prototype.readBoolean = function(name) {
    var temp,
        def;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readBoolean(0, true, def);
    return def
};
Taf.Wup.prototype.readInt8 = function(name) {
    var temp,
        def;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readInt8(0, true, def);
    return def
};
Taf.Wup.prototype.readInt16 = function(name) {
    var temp,
        def;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readInt16(0, true, def);
    return def
};
Taf.Wup.prototype.readInt32 = function(name) {
    var temp,
        def;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readInt32(0, true, def);
    return def
};
Taf.Wup.prototype.readInt64 = function(name) {
    var temp,
        def;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readInt64(0, true, def);
    return def
};
Taf.Wup.prototype.readFloat = function(name) {
    var temp,
        def;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readFloat(0, true, def);
    return def
};
Taf.Wup.prototype.readDouble = function(name) {
    var temp;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readDouble(0, true, def);
    return def
};
Taf.Wup.prototype.readVector = function(name, def, className) {
    var temp;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readVector(0, true, def);
    return def
};
Taf.Wup.prototype.readStruct = function(name, def, className) {
    var temp;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readStruct(0, true, def);
    return def
};
Taf.Wup.prototype.readMap = function(name, def, className) {
    var temp;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readMap(0, true, def);
    return def
};
Taf.Wup.prototype.readBytes = function(name, def, className) {
    var temp;
    temp = this.newdata.get(name);
    if (temp == undefined) {
        throw Error("UniAttribute not found key:" + name)
    }
    var is = this.iStream.setBuffer(temp.buffer);
    def = is.readBytes(0, true, def);
    return def
};
Taf.Util = Taf.Util || {};
Taf.Util.jcestream = function(value, col) {
    if (value == null || value == undefined) {
        logger.log("Taf.Util.jcestream::value is null or undefined");
        return
    }
    if (!(value instanceof ArrayBuffer)) {
        logger.log("Taf.Util.jcestream::value is not ArrayBuffer");
        return
    }
    col = col || 16;
    var view = new Uint8Array(value);
    var str = "";
    for (var i = 0; i < view.length; i++) {
        if (i != 0 && i % col == 0) {
            str += "\n"
        } else if (i != 0) {
            str += " "
        }
        str += (view[i] > 15 ? "" : "0") + view[i].toString(16)
    }
    logger.log(str.toUpperCase())
};
Taf.Util.str2ab = function(value) {
    var idx,
        len = value.length,
        arr = new Array(len);
    for (idx = 0; idx < len; ++idx) {
        arr[idx] = value.charCodeAt(idx)
    }
    return new Uint8Array(arr).buffer
};
Taf.Util.ajax = function(sURL, oData, oSuccFunc, oFailFunc) {
    var xmlobj = new XMLHttpRequest;
    xmlobj.overrideMimeType("text/plain; charset=x-user-defined");
    var handleStateChange = function() {
        if (xmlobj.readyState === 4) {
            if (xmlobj.status === 200 || xmlobj.status === 304) {
                oSuccFunc(Taf.Util.str2ab(xmlobj.response))
            } else {
                oFailFunc(xmlobj.status)
            }
            xmlobj.removeEventListener("readystatechange", handleStateChange);
            xmlobj = undefined
        }
    };
    xmlobj.addEventListener("readystatechange", handleStateChange);
    xmlobj.open("post", sURL);
    xmlobj.send(oData)
};
var HUYA = HUYA || {};
HUYA.REDIS_CONNECT_FAIL = -100;
HUYA.REDIS_COMMAND_FAIL = -101;
HUYA.REDIS_RECORD_NOT_EXIST = -102;
HUYA.UTSMD5KEY = "UI-TASK-USER,{8001EC79-E45F-4db7-9B82-9508463C3DCF}";
HUYA.TemplateType = {
    PRIMARY: 1,
    RECEPTION: 2
};
HUYA.ELiveSource = {
    PC_YY: 0,
    PC_HUYA: 1,
    MOBILE_HUYA: 2,
    WEB_HUYA: 3
};
HUYA.EWebSocketCommandType = {
    EWSCmd_NULL: 0,
    EWSCmd_RegisterReq: 1,
    EWSCmd_RegisterRsp: 2,
    EWSCmd_WupReq: 3,
    EWSCmd_WupRsp: 4,
    EWSCmdC2S_HeartBeat: 5,
    EWSCmdS2C_HeartBeatAck: 6,
    EWSCmdS2C_MsgPushReq: 7,
    EWSCmdC2S_DeregisterReq: 8,
    EWSCmdS2C_DeRegisterRsp: 9,
    EWSCmdC2S_VerifyCookieReq: 10,
    EWSCmdS2C_VerifyCookieRsp: 11,
    EWSCmdC2S_VerifyHuyaTokenReq: 12,
    EWSCmdS2C_VerifyHuyaTokenRsp: 13,
    EWSCmdC2S_UNVerifyReq: 14,
    EWSCmdS2C_UNVerifyRsp: 15,
    EWSCmdC2S_RegisterGroupReq: 16,
    EWSCmdS2C_RegisterGroupRsp: 17,
    EWSCmdC2S_UnRegisterGroupReq: 18,
    EWSCmdS2C_UnRegisterGroupRsp: 19,
    EWSCmdC2S_HeartBeatReq: 20,
    EWSCmdS2C_HeartBeatRsp: 21,
    EWSCmdS2C_MsgPushReq_V2: 22
};
HUYA.SecPackType = {
    kSecPackTypeActivityMsgNotice: 1010003
};
HUYA.UserId = function() {
    this.lUid = 0;
    this.sGuid = "";
    this.sToken = "";
    this.sHuYaUA = "";
    this.sCookie = "";
    this.iTokenType = 0
};
HUYA.UserId.prototype._clone = function() {
    return new HUYA.UserId
};
HUYA.UserId.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.UserId.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.UserId.prototype.writeTo = function(os) {
    os.writeInt64(0, this.lUid);
    os.writeString(1, this.sGuid);
    os.writeString(2, this.sToken);
    os.writeString(3, this.sHuYaUA);
    os.writeString(4, this.sCookie);
    os.writeInt32(5, this.iTokenType)
};
HUYA.UserId.prototype.readFrom = function(is) {
    this.lUid = is.readInt64(0, false, this.lUid);
    this.sGuid = is.readString(1, false, this.sGuid);
    this.sToken = is.readString(2, false, this.sToken);
    this.sHuYaUA = is.readString(3, false, this.sHuYaUA);
    this.sCookie = is.readString(4, false, this.sCookie);
    this.iTokenType = is.readInt32(5, false, this.iTokenType)
};
HUYA.UserInfo = function() {
    this.lUid = 0;
    this.vHuyaB = new Taf.Vector(new Taf.INT32);
    this.iResignCard = 0;
    this.iExp = 0;
    this.iLevel = 0;
    this.iCurLevelExp = 0;
    this.iNextLevelExp = 0;
    this.iHuyaB = 0;
    this.iSignTaskStat = 0;
    this.iWatchLiveStat = 0;
    this.iLevelTaskStat = 0;
    this.vTaskStatus = new Taf.Vector(new HUYA.DailyTaskStatus)
};
HUYA.UserInfo.prototype._clone = function() {
    return new HUYA.UserInfo
};
HUYA.UserInfo.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.UserInfo.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.UserInfo.prototype.writeTo = function(os) {
    os.writeInt64(0, this.lUid);
    os.writeVector(1, this.vHuyaB);
    os.writeInt32(2, this.iResignCard);
    os.writeInt32(3, this.iExp);
    os.writeInt32(4, this.iLevel);
    os.writeInt32(5, this.iCurLevelExp);
    os.writeInt32(6, this.iNextLevelExp);
    os.writeInt32(7, this.iHuyaB);
    os.writeInt32(8, this.iSignTaskStat);
    os.writeInt32(9, this.iWatchLiveStat);
    os.writeInt32(10, this.iLevelTaskStat);
    os.writeVector(11, this.vTaskStatus)
};
HUYA.UserInfo.prototype.readFrom = function(is) {
    this.lUid = is.readInt64(0, false, this.lUid);
    this.vHuyaB = is.readVector(1, false, this.vHuyaB);
    this.iResignCard = is.readInt32(2, false, this.iResignCard);
    this.iExp = is.readInt32(3, false, this.iExp);
    this.iLevel = is.readInt32(4, false, this.iLevel);
    this.iCurLevelExp = is.readInt32(5, false, this.iCurLevelExp);
    this.iNextLevelExp = is.readInt32(6, false, this.iNextLevelExp);
    this.iHuyaB = is.readInt32(7, false, this.iHuyaB);
    this.iSignTaskStat = is.readInt32(8, false, this.iSignTaskStat);
    this.iWatchLiveStat = is.readInt32(9, false, this.iWatchLiveStat);
    this.iLevelTaskStat = is.readInt32(10, false, this.iLevelTaskStat);
    this.vTaskStatus = is.readVector(11, false, this.vTaskStatus)
};
HUYA.WSUserInfo = function() {
    this.lUid = 0;
    this.bAnonymous = true;
    this.sGuid = "";
    this.sToken = "";
    this.lTid = 0;
    this.lSid = 0;
    this.lGroupId = 0;
    this.lGroupType = 0;
    this.sAppId = ""
};
HUYA.WSUserInfo.prototype._clone = function() {
    return new HUYA.WSUserInfo
};
HUYA.WSUserInfo.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSUserInfo.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSUserInfo.prototype.writeTo = function(os) {
    os.writeInt64(0, this.lUid);
    os.writeBoolean(1, this.bAnonymous);
    os.writeString(2, this.sGuid);
    os.writeString(3, this.sToken);
    os.writeInt64(4, this.lTid);
    os.writeInt64(5, this.lSid);
    os.writeInt64(6, this.lGroupId);
    os.writeInt64(7, this.lGroupType);
    os.writeString(8, this.sAppId)
};
HUYA.WSUserInfo.prototype.readFrom = function(is) {
    this.lUid = is.readInt64(0, false, this.lUid);
    this.bAnonymous = is.readBoolean(1, false, this.bAnonymous);
    this.sGuid = is.readString(2, false, this.sGuid);
    this.sToken = is.readString(3, false, this.sToken);
    this.lTid = is.readInt64(4, false, this.lTid);
    this.lSid = is.readInt64(5, false, this.lSid);
    this.lGroupId = is.readInt64(6, false, this.lGroupId);
    this.lGroupType = is.readInt64(7, false, this.lGroupType);
    this.sAppId = is.readString(8, false, this.sAppId)
};
HUYA.WSRegisterRsp = function() {
    this.iResCode = 0;
    this.lRequestId = 0;
    this.sMessage = "";
    this.sBCConnHost = ""
};
HUYA.WSRegisterRsp.prototype._clone = function() {
    return new HUYA.WSRegisterRsp
};
HUYA.WSRegisterRsp.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSRegisterRsp.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSRegisterRsp.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iResCode);
    os.writeInt64(1, this.lRequestId);
    os.writeString(2, this.sMessage);
    os.writeString(3, this.sBCConnHost)
};
HUYA.WSRegisterRsp.prototype.readFrom = function(is) {
    this.iResCode = is.readInt32(0, false, this.iResCode);
    this.lRequestId = is.readInt64(1, false, this.lRequestId);
    this.sMessage = is.readString(2, false, this.sMessage);
    this.sBCConnHost = is.readString(3, false, this.sBCConnHost)
};
HUYA.WebSocketCommand = function() {
    this.iCmdType = 0;
    this.vData = new Taf.BinBuffer;
    this.lRequestId = 0;
    this.traceId = ""
};
HUYA.WebSocketCommand.prototype._clone = function() {
    return new HUYA.WebSocketCommand
};
HUYA.WebSocketCommand.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WebSocketCommand.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WebSocketCommand.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iCmdType);
    os.writeBytes(1, this.vData);
    os.writeInt64(2, this.lRequestId);
    os.writeString(3, this.traceId)
};
HUYA.WebSocketCommand.prototype.readFrom = function(is) {
    this.iCmdType = is.readInt32(0, false, this.iCmdType);
    this.vData = is.readBytes(1, false, this.vData);
    this.lRequestId = is.readInt64(2, false, this.lRequestId);
    this.traceId = is.readString(3, false, this.traceId)
};
HUYA.WSPushMessage = function() {
    this.ePushType = 0;
    this.iUri = 0;
    this.sMsg = new Taf.BinBuffer;
    this.iProtocolType = 0;
    this.sGroupId = "";
    this.lMsgId = 0
};
HUYA.WSPushMessage.prototype._clone = function() {
    return new HUYA.WSPushMessage
};
HUYA.WSPushMessage.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSPushMessage.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSPushMessage.prototype.writeTo = function(os) {
    os.writeInt32(0, this.ePushType);
    os.writeInt64(1, this.iUri);
    os.writeBytes(2, this.sMsg);
    os.writeInt32(3, this.iProtocolType);
    os.writeString(4, this.sGroupId);
    os.writeInt64(5, this.lMsgId)
};
HUYA.WSPushMessage.prototype.readFrom = function(is) {
    this.ePushType = is.readInt32(0, false, this.ePushType);
    this.iUri = is.readInt64(1, false, this.iUri);
    this.sMsg = is.readBytes(2, false, this.sMsg);
    this.iProtocolType = is.readInt32(3, false, this.iProtocolType);
    this.sGroupId = is.readString(4, false, this.sGroupId);
    this.lMsgId = is.readInt64(5, false, this.lMsgId)
};
HUYA.WSHeartBeat = function() {
    this.iState = 0
};
HUYA.WSHeartBeat.prototype._clone = function() {
    return new HUYA.WSHeartBeat
};
HUYA.WSHeartBeat.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSHeartBeat.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSHeartBeat.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iState)
};
HUYA.WSHeartBeat.prototype.readFrom = function(is) {
    this.iState = is.readInt32(0, false, this.iState)
};
HUYA.LiveAppUAEx = function() {
    this.sIMEI = "";
    this.sAPN = "";
    this.sNetType = ""
};
HUYA.LiveAppUAEx.prototype._clone = function() {
    return new HUYA.LiveAppUAEx
};
HUYA.LiveAppUAEx.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.LiveAppUAEx.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.LiveAppUAEx.prototype.writeTo = function(os) {
    os.writeString(1, this.sIMEI);
    os.writeString(2, this.sAPN);
    os.writeString(3, this.sNetType)
};
HUYA.LiveAppUAEx.prototype.readFrom = function(is) {
    this.sIMEI = is.readString(1, false, this.sIMEI);
    this.sAPN = is.readString(2, false, this.sAPN);
    this.sNetType = is.readString(3, false, this.sNetType)
};
HUYA.LiveUserbase = function() {
    this.eSource = 0;
    this.eType = 0;
    this.tUAEx = new HUYA.LiveAppUAEx
};
HUYA.LiveUserbase.prototype._clone = function() {
    return new HUYA.LiveUserbase
};
HUYA.LiveUserbase.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.LiveUserbase.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.LiveUserbase.prototype.writeTo = function(os) {
    os.writeInt32(0, this.eSource);
    os.writeInt32(1, this.eType);
    os.writeStruct(2, this.tUAEx)
};
HUYA.LiveUserbase.prototype.readFrom = function(is) {
    this.eSource = is.readInt32(0, false, this.eSource);
    this.eType = is.readInt32(1, false, this.eType);
    this.tUAEx = is.readStruct(2, false, this.tUAEx)
};
HUYA.LiveLaunchReq = function() {
    this.tId = new HUYA.UserId;
    this.tLiveUB = new HUYA.LiveUserbase;
    this.bSupportDomain = 0
};
HUYA.LiveLaunchReq.prototype._clone = function() {
    return new HUYA.LiveLaunchReq
};
HUYA.LiveLaunchReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.LiveLaunchReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.LiveLaunchReq.prototype.writeTo = function(os) {
    os.writeStruct(0, this.tId);
    os.writeStruct(1, this.tLiveUB);
    os.writeInt32(2, this.bSupportDomain)
};
HUYA.LiveLaunchReq.prototype.readFrom = function(is) {
    this.tId = is.readStruct(0, false, this.tId);
    this.tLiveUB = is.readStruct(1, false, this.tLiveUB);
    this.bSupportDomain = is.readInt32(2, false, this.bSupportDomain)
};
HUYA.LiveProxyValue = function() {
    this.eProxyType = 0;
    this.sProxy = new Taf.Vector(new Taf.STRING)
};
HUYA.LiveProxyValue.prototype._clone = function() {
    return new HUYA.LiveProxyValue
};
HUYA.LiveProxyValue.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.LiveProxyValue.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.LiveProxyValue.prototype.writeTo = function(os) {
    os.writeInt32(0, this.eProxyType);
    os.writeVector(1, this.sProxy)
};
HUYA.LiveProxyValue.prototype.readFrom = function(is) {
    this.eProxyType = is.readInt32(0, false, this.eProxyType);
    this.sProxy = is.readVector(1, false, this.sProxy)
};
HUYA.LiveLaunchRsp = function() {
    this.sGuid = "";
    this.iTime = 0;
    this.vProxyList = new Taf.Vector(new HUYA.LiveProxyValue);
    this.eAccess = 0;
    this.sClientIp = ""
};
HUYA.LiveLaunchRsp.prototype._clone = function() {
    return new HUYA.LiveLaunchRsp
};
HUYA.LiveLaunchRsp.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.LiveLaunchRsp.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.LiveLaunchRsp.prototype.writeTo = function(os) {
    os.writeString(0, this.sGuid);
    os.writeInt32(1, this.iTime);
    os.writeVector(2, this.vProxyList);
    os.writeInt32(3, this.eAccess);
    os.writeString(4, this.sClientIp)
};
HUYA.LiveLaunchRsp.prototype.readFrom = function(is) {
    this.sGuid = is.readString(0, false, this.sGuid);
    this.iTime = is.readInt32(1, false, this.iTime);
    this.vProxyList = is.readVector(2, false, this.vProxyList);
    this.eAccess = is.readInt32(3, false, this.eAccess);
    this.sClientIp = is.readString(4, false, this.sClientIp)
};
HUYA.WSVerifyCookieReq = function() {
    this.lUid = 0;
    this.sUA = "";
    this.sCookie = ""
};
HUYA.WSVerifyCookieReq.prototype._clone = function() {
    return new HUYA.WSVerifyCookieReq
};
HUYA.WSVerifyCookieReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSVerifyCookieReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSVerifyCookieReq.prototype.writeTo = function(os) {
    os.writeInt64(0, this.lUid);
    os.writeString(1, this.sUA);
    os.writeString(2, this.sCookie)
};
HUYA.WSVerifyCookieReq.prototype.readFrom = function(is) {
    this.lUid = is.readInt64(0, false, this.lUid);
    this.sUA = is.readString(1, false, this.sUA);
    this.sCookie = is.readString(2, false, this.sCookie)
};
HUYA.WSVerifyCookieRsp = function() {
    this.iValidate = 0
};
HUYA.WSVerifyCookieRsp.prototype._clone = function() {
    return new HUYA.WSVerifyCookieRsp
};
HUYA.WSVerifyCookieRsp.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSVerifyCookieRsp.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSVerifyCookieRsp.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iValidate)
};
HUYA.WSVerifyCookieRsp.prototype.readFrom = function(is) {
    this.iValidate = is.readInt32(0, false, this.iValidate)
};
HUYA.WSPushMessage_V2 = function() {
    this.sGroupId = "";
    this.vMsgItem = new Taf.Vector(new HUYA.WSMsgItem)
};
HUYA.WSPushMessage_V2.prototype._clone = function() {
    return new HUYA.WSPushMessage_V2
};
HUYA.WSPushMessage_V2.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSPushMessage_V2.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSPushMessage_V2.prototype.writeTo = function(os) {
    os.writeString(0, this.sGroupId);
    os.writeVector(1, this.vMsgItem)
};
HUYA.WSPushMessage_V2.prototype.readFrom = function(is) {
    this.sGroupId = is.readString(0, false, this.sGroupId);
    this.vMsgItem = is.readVector(1, false, this.vMsgItem)
};
HUYA.WSRegisterGroupReq = function() {
    this.vGroupId = new Taf.Vector(new Taf.STRING);
    this.sToken = ""
};
HUYA.WSRegisterGroupReq.prototype._clone = function() {
    return new HUYA.WSRegisterGroupReq
};
HUYA.WSRegisterGroupReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSRegisterGroupReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSRegisterGroupReq.prototype.writeTo = function(os) {
    os.writeVector(0, this.vGroupId);
    os.writeString(1, this.sToken)
};
HUYA.WSRegisterGroupReq.prototype.readFrom = function(is) {
    this.vGroupId = is.readVector(0, false, this.vGroupId);
    this.sToken = is.readString(1, false, this.sToken)
};
HUYA.WSRegisterGroupRsp = function() {
    this.iResCode = 0
};
HUYA.WSRegisterGroupRsp.prototype._clone = function() {
    return new HUYA.WSRegisterGroupRsp
};
HUYA.WSRegisterGroupRsp.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSRegisterGroupRsp.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSRegisterGroupRsp.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iResCode)
};
HUYA.WSRegisterGroupRsp.prototype.readFrom = function(is) {
    this.iResCode = is.readInt32(0, false, this.iResCode)
};
HUYA.WSUnRegisterGroupReq = function() {
    this.vGroupId = new Taf.Vector(new Taf.STRING)
};
HUYA.WSUnRegisterGroupReq.prototype._clone = function() {
    return new HUYA.WSUnRegisterGroupReq
};
HUYA.WSUnRegisterGroupReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSUnRegisterGroupReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSUnRegisterGroupReq.prototype.writeTo = function(os) {
    os.writeVector(0, this.vGroupId)
};
HUYA.WSUnRegisterGroupReq.prototype.readFrom = function(is) {
    this.vGroupId = is.readVector(0, false, this.vGroupId)
};
HUYA.WSUnRegisterGroupRsp = function() {
    this.iResCode = 0
};
HUYA.WSUnRegisterGroupRsp.prototype._clone = function() {
    return new HUYA.WSUnRegisterGroupRsp
};
HUYA.WSUnRegisterGroupRsp.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSUnRegisterGroupRsp.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSUnRegisterGroupRsp.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iResCode)
};
HUYA.WSUnRegisterGroupRsp.prototype.readFrom = function(is) {
    this.iResCode = is.readInt32(0, false, this.iResCode)
};
HUYA.WSMsgItem = function() {
    this.iUri = 0;
    this.sMsg = new Taf.BinBuffer;
    this.lMsgId = 0
};
HUYA.WSMsgItem.prototype._clone = function() {
    return new HUYA.WSMsgItem
};
HUYA.WSMsgItem.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.WSMsgItem.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.WSMsgItem.prototype.writeTo = function(os) {
    os.writeInt64(0, this.iUri);
    os.writeBytes(1, this.sMsg);
    os.writeInt64(2, this.lMsgId)
};
HUYA.WSMsgItem.prototype.readFrom = function(is) {
    this.iUri = is.readInt64(0, false, this.iUri);
    this.sMsg = is.readBytes(1, false, this.sMsg);
    this.lMsgId = is.readInt64(2, false, this.lMsgId)
};
HUYA.EnterChannelReq = function() {
    this.tUserId = new HUYA.UserId;
    this.lTid = 0;
    this.lSid = 0;
    this.iChannelType = 0
};
HUYA.EnterChannelReq.prototype._clone = function() {
    return new HUYA.EnterChannelReq
};
HUYA.EnterChannelReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.EnterChannelReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.EnterChannelReq.prototype.writeTo = function(os) {
    os.writeStruct(1, this.tUserId);
    os.writeInt64(2, this.lTid);
    os.writeInt64(3, this.lSid);
    os.writeInt32(4, this.iChannelType)
};
HUYA.EnterChannelReq.prototype.readFrom = function(is) {
    this.tUserId = is.readStruct(1, false, this.tUserId);
    this.lTid = is.readInt64(2, false, this.lTid);
    this.lSid = is.readInt64(3, false, this.lSid);
    this.iChannelType = is.readInt32(4, false, this.iChannelType)
};
HUYA.ActivityMsgReq = function() {
    this.tUserId = new HUYA.UserId;
    this.iActivityId = 0;
    this.lPid = 0;
    this.lTid = 0;
    this.lSid = 0;
    this.iChannelType = 0;
    this.iSubUri = 0
};
HUYA.ActivityMsgReq.prototype._clone = function() {
    return new HUYA.ActivityMsgReq
};
HUYA.ActivityMsgReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.ActivityMsgReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.ActivityMsgReq.prototype.writeTo = function(os) {
    os.writeStruct(0, this.tUserId);
    os.writeInt32(1, this.iActivityId);
    os.writeInt64(2, this.lPid);
    os.writeInt64(3, this.lTid);
    os.writeInt64(4, this.lSid);
    os.writeInt32(5, this.iChannelType);
    os.writeInt32(6, this.iSubUri)
};
HUYA.ActivityMsgReq.prototype.readFrom = function(is) {
    this.tUserId = is.readStruct(0, false, this.tUserId);
    this.iActivityId = is.readInt32(1, false, this.iActivityId);
    this.lPid = is.readInt64(2, false, this.lPid);
    this.lTid = is.readInt64(3, false, this.lTid);
    this.lSid = is.readInt64(4, false, this.lSid);
    this.iChannelType = is.readInt32(5, false, this.iChannelType);
    this.iSubUri = is.readInt32(6, false, this.iSubUri)
};
HUYA.ActivitySerializedMsg = function() {
    this.iSubUri = 0;
    this.vContent = new Taf.BinBuffer
};
HUYA.ActivitySerializedMsg.prototype._clone = function() {
    return new HUYA.ActivitySerializedMsg
};
HUYA.ActivitySerializedMsg.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.ActivitySerializedMsg.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.ActivitySerializedMsg.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iSubUri);
    os.writeBytes(1, this.vContent)
};
HUYA.ActivitySerializedMsg.prototype.readFrom = function(is) {
    this.iSubUri = is.readInt32(0, false, this.iSubUri);
    this.vContent = is.readBytes(1, false, this.vContent)
};
HUYA.ActivityMsgRsp = function() {
    this.iEnable = 0;
    this.vSerializedMsg = new Taf.Vector(new HUYA.ActivitySerializedMsg);
    this.iTimeStamp = 0
};
HUYA.ActivityMsgRsp.prototype._clone = function() {
    return new HUYA.ActivityMsgRsp
};
HUYA.ActivityMsgRsp.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.ActivityMsgRsp.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.ActivityMsgRsp.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iEnable);
    os.writeVector(1, this.vSerializedMsg);
    os.writeInt32(2, this.iTimeStamp)
};
HUYA.ActivityMsgRsp.prototype.readFrom = function(is) {
    this.iEnable = is.readInt32(0, false, this.iEnable);
    this.vSerializedMsg = is.readVector(1, false, this.vSerializedMsg);
    this.iTimeStamp = is.readInt32(2, false, this.iTimeStamp)
};
HUYA.PresenterChannelInfo = function() {
    this.lYYId = 0;
    this.lTid = 0;
    this.lSid = 0;
    this.iSourceType = 0;
    this.iScreenType = 0;
    this.lUid = 0;
    this.iGameId = 0
};
HUYA.PresenterChannelInfo.prototype._clone = function() {
    return new HUYA.PresenterChannelInfo
};
HUYA.PresenterChannelInfo.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.PresenterChannelInfo.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.PresenterChannelInfo.prototype.writeTo = function(os) {
    os.writeInt64(0, this.lYYId);
    os.writeInt64(1, this.lTid);
    os.writeInt64(3, this.lSid);
    os.writeInt32(4, this.iSourceType);
    os.writeInt32(5, this.iScreenType);
    os.writeInt64(6, this.lUid);
    os.writeInt32(7, this.iGameId)
};
HUYA.PresenterChannelInfo.prototype.readFrom = function(is) {
    this.lYYId = is.readInt64(0, false, this.lYYId);
    this.lTid = is.readInt64(1, false, this.lTid);
    this.lSid = is.readInt64(3, false, this.lSid);
    this.iSourceType = is.readInt32(4, false, this.iSourceType);
    this.iScreenType = is.readInt32(5, false, this.iScreenType);
    this.lUid = is.readInt64(6, false, this.lUid);
    this.iGameId = is.readInt32(7, false, this.iGameId)
};
HUYA.BadgeReq = function() {
    this.tUserId = new HUYA.UserId;
    this.lBadgeId = 0;
    this.lToUid = 0
};
HUYA.BadgeReq.prototype._clone = function() {
    return new HUYA.BadgeReq
};
HUYA.BadgeReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.BadgeReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.BadgeReq.prototype.writeTo = function(os) {
    os.writeStruct(0, this.tUserId);
    os.writeInt64(1, this.lBadgeId);
    os.writeInt64(2, this.lToUid)
};
HUYA.BadgeReq.prototype.readFrom = function(is) {
    this.tUserId = is.readStruct(0, false, this.tUserId);
    this.lBadgeId = is.readInt64(1, false, this.lBadgeId);
    this.lToUid = is.readInt64(2, false, this.lToUid)
};
HUYA.BadgeInfo = function() {
    this.lUid = 0;
    this.lBadgeId = 0;
    this.sPresenterNickName = "";
    this.sBadgeName = "";
    this.iBadgeLevel = 0;
    this.iRank = 0;
    this.iScore = 0;
    this.iNextScore = 0;
    this.iQuotaUsed = 0;
    this.iQuota = 0;
    this.lQuotaTS = 0;
    this.lOpenTS = 0;
    this.iVFlag = 0;
    this.sVLogo = "";
    this.tChannelInfo = new HUYA.PresenterChannelInfo;
    this.sPresenterLogo = "";
    this.lVExpiredTS = 0
};
HUYA.BadgeInfo.prototype._clone = function() {
    return new HUYA.BadgeInfo
};
HUYA.BadgeInfo.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.BadgeInfo.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.BadgeInfo.prototype.writeTo = function(os) {
    os.writeInt64(0, this.lUid);
    os.writeInt64(1, this.lBadgeId);
    os.writeString(2, this.sPresenterNickName);
    os.writeString(3, this.sBadgeName);
    os.writeInt32(4, this.iBadgeLevel);
    os.writeInt32(5, this.iRank);
    os.writeInt32(6, this.iScore);
    os.writeInt32(7, this.iNextScore);
    os.writeInt32(8, this.iQuotaUsed);
    os.writeInt32(9, this.iQuota);
    os.writeInt64(10, this.lQuotaTS);
    os.writeInt64(11, this.lOpenTS);
    os.writeInt32(12, this.iVFlag);
    os.writeString(13, this.sVLogo);
    os.writeStruct(14, this.tChannelInfo);
    os.writeString(15, this.sPresenterLogo);
    os.writeInt64(16, this.lVExpiredTS)
};
HUYA.BadgeInfo.prototype.readFrom = function(is) {
    this.lUid = is.readInt64(0, false, this.lUid);
    this.lBadgeId = is.readInt64(1, false, this.lBadgeId);
    this.sPresenterNickName = is.readString(2, false, this.sPresenterNickName);
    this.sBadgeName = is.readString(3, false, this.sBadgeName);
    this.iBadgeLevel = is.readInt32(4, false, this.iBadgeLevel);
    this.iRank = is.readInt32(5, false, this.iRank);
    this.iScore = is.readInt32(6, false, this.iScore);
    this.iNextScore = is.readInt32(7, false, this.iNextScore);
    this.iQuotaUsed = is.readInt32(8, false, this.iQuotaUsed);
    this.iQuota = is.readInt32(9, false, this.iQuota);
    this.lQuotaTS = is.readInt64(10, false, this.lQuotaTS);
    this.lOpenTS = is.readInt64(11, false, this.lOpenTS);
    this.iVFlag = is.readInt32(12, false, this.iVFlag);
    this.sVLogo = is.readString(13, false, this.sVLogo);
    this.tChannelInfo = is.readStruct(14, false, this.tChannelInfo);
    this.sPresenterLogo = is.readString(15, false, this.sPresenterLogo);
    this.lVExpiredTS = is.readInt64(16, false, this.lVExpiredTS)
};
HUYA.SendCardPackageItemReq = function() {
    this.tId = new HUYA.UserId;
    this.lSid = 0;
    this.lSubSid = 0;
    this.iShowFreeitemInfo = 0;
    this.iItemType = 0;
    this.iItemCount = 0;
    this.lPresenterUid = 0;
    this.sPayId = "";
    this.sSendContent = "";
    this.sSenderNick = "";
    this.sPresenterNick = "";
    this.iPayPloy = 0;
    this.iItemCountByGroup = 0;
    this.iItemGroup = 0;
    this.iSuperPupleLevel = 0;
    this.iFromType = 0;
    this.sExpand = "";
    this.sToken = "";
    this.iTemplateType = 0;
    this.sTokencaKey = "";
    this.sPassport = "";
    this.iSenderShortSid = 0;
    this.iPayByFreeItem = 0;
    this.tExtUser = new HUYA.ExternalUser;
    this.iEventType = 0
};
HUYA.SendCardPackageItemReq.prototype._clone = function() {
    return new HUYA.SendCardPackageItemReq
};
HUYA.SendCardPackageItemReq.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.SendCardPackageItemReq.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.SendCardPackageItemReq.prototype.writeTo = function(os) {
    os.writeStruct(0, this.tId);
    os.writeInt64(1, this.lSid);
    os.writeInt64(2, this.lSubSid);
    os.writeInt32(3, this.iShowFreeitemInfo);
    os.writeInt32(4, this.iItemType);
    os.writeInt32(5, this.iItemCount);
    os.writeInt64(6, this.lPresenterUid);
    os.writeString(7, this.sPayId);
    os.writeString(9, this.sSendContent);
    os.writeString(10, this.sSenderNick);
    os.writeString(11, this.sPresenterNick);
    os.writeInt32(12, this.iPayPloy);
    os.writeInt32(13, this.iItemCountByGroup);
    os.writeInt32(14, this.iItemGroup);
    os.writeInt32(15, this.iSuperPupleLevel);
    os.writeInt32(16, this.iFromType);
    os.writeString(17, this.sExpand);
    os.writeString(18, this.sToken);
    os.writeInt32(19, this.iTemplateType);
    os.writeString(20, this.sTokencaKey);
    os.writeString(21, this.sPassport);
    os.writeInt64(22, this.iSenderShortSid);
    os.writeInt32(23, this.iPayByFreeItem);
    os.writeStruct(24, this.tExtUser);
    os.writeInt16(25, this.iEventType)
};
HUYA.SendCardPackageItemReq.prototype.readFrom = function(is) {
    this.tId = is.readStruct(0, false, this.tId);
    this.lSid = is.readInt64(1, false, this.lSid);
    this.lSubSid = is.readInt64(2, false, this.lSubSid);
    this.iShowFreeitemInfo = is.readInt32(3, false, this.iShowFreeitemInfo);
    this.iItemType = is.readInt32(4, false, this.iItemType);
    this.iItemCount = is.readInt32(5, false, this.iItemCount);
    this.lPresenterUid = is.readInt64(6, false, this.lPresenterUid);
    this.sPayId = is.readString(7, false, this.sPayId);
    this.sSendContent = is.readString(9, false, this.sSendContent);
    this.sSenderNick = is.readString(10, false, this.sSenderNick);
    this.sPresenterNick = is.readString(11, false, this.sPresenterNick);
    this.iPayPloy = is.readInt32(12, false, this.iPayPloy);
    this.iItemCountByGroup = is.readInt32(13, false, this.iItemCountByGroup);
    this.iItemGroup = is.readInt32(14, false, this.iItemGroup);
    this.iSuperPupleLevel = is.readInt32(15, false, this.iSuperPupleLevel);
    this.iFromType = is.readInt32(16, false, this.iFromType);
    this.sExpand = is.readString(17, false, this.sExpand);
    this.sToken = is.readString(18, false, this.sToken);
    this.iTemplateType = is.readInt32(19, false, this.iTemplateType);
    this.sTokencaKey = is.readString(20, false, this.sTokencaKey);
    this.sPassport = is.readString(21, false, this.sPassport);
    this.iSenderShortSid = is.readInt64(22, false, this.iSenderShortSid);
    this.iPayByFreeItem = is.readInt32(23, false, this.iPayByFreeItem);
    this.tExtUser = is.readStruct(24, false, this.tExtUser);
    this.iEventType = is.readInt16(25, false, this.iEventType)
};
HUYA.SendCardPackageItemRsp = function() {
    this.iPayRespCode = 0;
    this.iItemType = 0;
    this.iItemCount = 0;
    this.strPayId = "";
    this.strPayConfirmUrl = "";
    this.strSendContent = "";
    this.iItemCountByGroup = 0;
    this.iItemGroup = 0;
    this.lPresenterUid = 0;
    this.sExpand = "";
    this.strPayItemInfo = "";
    this.iPayType = 0
};
HUYA.SendCardPackageItemRsp.prototype._clone = function() {
    return new HUYA.SendCardPackageItemRsp
};
HUYA.SendCardPackageItemRsp.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.SendCardPackageItemRsp.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.SendCardPackageItemRsp.prototype.writeTo = function(os) {
    os.writeInt32(0, this.iPayRespCode);
    os.writeInt32(1, this.iItemType);
    os.writeInt32(2, this.iItemCount);
    os.writeString(3, this.strPayId);
    os.writeString(4, this.strPayConfirmUrl);
    os.writeString(5, this.strSendContent);
    os.writeInt32(6, this.iItemCountByGroup);
    os.writeInt32(7, this.iItemGroup);
    os.writeInt64(8, this.lPresenterUid);
    os.writeString(9, this.sExpand);
    os.writeString(10, this.strPayItemInfo);
    os.writeInt32(11, this.iPayType)
};
HUYA.SendCardPackageItemRsp.prototype.readFrom = function(is) {
    this.iPayRespCode = is.readInt32(0, false, this.iPayRespCode);
    this.iItemType = is.readInt32(1, false, this.iItemType);
    this.iItemCount = is.readInt32(2, false, this.iItemCount);
    this.strPayId = is.readString(3, false, this.strPayId);
    this.strPayConfirmUrl = is.readString(4, false, this.strPayConfirmUrl);
    this.strSendContent = is.readString(5, false, this.strSendContent);
    this.iItemCountByGroup = is.readInt32(6, false, this.iItemCountByGroup);
    this.iItemGroup = is.readInt32(7, false, this.iItemGroup);
    this.lPresenterUid = is.readInt64(8, false, this.lPresenterUid);
    this.sExpand = is.readString(9, false, this.sExpand);
    this.strPayItemInfo = is.readString(10, false, this.strPayItemInfo);
    this.iPayType = is.readInt32(11, false, this.iPayType)
};
HUYA.ExternalUser = function() {
    this.sId = "";
    this.sToken = "";
    this.sOther = ""
};
HUYA.ExternalUser.prototype._clone = function() {
    return new HUYA.ExternalUser
};
HUYA.ExternalUser.prototype._write = function(os, tag, value) {
    os.writeStruct(tag, value)
};
HUYA.ExternalUser.prototype._read = function(is, tag, def) {
    return is.readStruct(tag, true, def)
};
HUYA.ExternalUser.prototype.writeTo = function(os) {
    os.writeString(0, this.sId);
    os.writeString(1, this.sToken);
    os.writeString(2, this.sOther)
};
HUYA.ExternalUser.prototype.readFrom = function(is) {
    this.sId = is.readString(0, false, this.sId);
    this.sToken = is.readString(1, false, this.sToken);
    this.sOther = is.readString(2, false, this.sOther)
};


var DM = DM || {};
DM.MessageNotice = function() {
    this.tUserInfo = new DM.SenderInfo,
    this.lTid = 0,
    this.lSid = 0,
    this.sContent = "",
    this.iShowMode = 0,
    this.tFormat = new DM.ContentFormat,
    this.tBulletFormat = new DM.BulletFormat,
    this.iTermType = 0,
    this.vDecorationPrefix = new Taf.Vector(new DM.DecorationInfo),
    this.vDecorationSuffix = new Taf.Vector(new DM.DecorationInfo),
    this.vAtSomeone = new Taf.Vector(new DM.UidNickName),
    this.lPid = 0,
    this.vBulletPrefix = new Taf.Vector(new DM.DecorationInfo),
    this.sIconUrl = "",
    this.iType = 0,
    this.vBulletSuffix = new Taf.Vector(new DM.DecorationInfo),
    this.vTagInfo = new Taf.Vector(new DM.MessageTagInfo),
    this.tSenceFormat = new DM.SendMessageFormat
};
DM.MessageNotice.prototype._clone = function() {
    return new DM.MessageNotice
};
DM.MessageNotice.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.MessageNotice.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.MessageNotice.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tUserInfo),
    t.writeInt64(1, this.lTid),
    t.writeInt64(2, this.lSid),
    t.writeString(3, this.sContent),
    t.writeInt32(4, this.iShowMode),
    t.writeStruct(5, this.tFormat),
    t.writeStruct(6, this.tBulletFormat),
    t.writeInt32(7, this.iTermType),
    t.writeVector(8, this.vDecorationPrefix),
    t.writeVector(9, this.vDecorationSuffix),
    t.writeVector(10, this.vAtSomeone),
    t.writeInt64(11, this.lPid),
    t.writeVector(12, this.vBulletPrefix),
    t.writeString(13, this.sIconUrl),
    t.writeInt32(14, this.iType),
    t.writeVector(15, this.vBulletSuffix),
    t.writeVector(16, this.vTagInfo),
    t.writeStruct(17, this.tSenceFormat)
};
DM.MessageNotice.prototype.readFrom = function(t) {
    this.tUserInfo = t.readStruct(0, !1, this.tUserInfo),
    this.lTid = t.readInt64(1, !1, this.lTid),
    this.lSid = t.readInt64(2, !1, this.lSid),
    this.sContent = t.readString(3, !1, this.sContent),
    this.iShowMode = t.readInt32(4, !1, this.iShowMode),
    this.tFormat = t.readStruct(5, !1, this.tFormat),
    this.tBulletFormat = t.readStruct(6, !1, this.tBulletFormat),
    this.iTermType = t.readInt32(7, !1, this.iTermType),
    this.vDecorationPrefix = t.readVector(8, !1, this.vDecorationPrefix),
    this.vDecorationSuffix = t.readVector(9, !1, this.vDecorationSuffix),
    this.vAtSomeone = t.readVector(10, !1, this.vAtSomeone),
    this.lPid = t.readInt64(11, !1, this.lPid),
    this.vBulletPrefix = t.readVector(12, !1, this.vBulletPrefix),
    this.sIconUrl = t.readString(13, !1, this.sIconUrl),
    this.iType = t.readInt32(14, !1, this.iType),
    this.vBulletSuffix = t.readVector(15, !1, this.vBulletSuffix),
    this.vTagInfo = t.readVector(16, !1, this.vTagInfo),
    this.tSenceFormat = t.readStruct(17, !1, this.tSenceFormat)
};

DM.MessageTagInfo = function() {
    this.iAppId = 0,
    this.sTag = ""
};
DM.MessageTagInfo.prototype._clone = function() {
    return new DM.MessageTagInfo
};
DM.MessageTagInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.MessageTagInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.MessageTagInfo.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iAppId),
    t.writeString(1, this.sTag)
};
DM.MessageTagInfo.prototype.readFrom = function(t) {
    this.iAppId = t.readInt32(0, !1, this.iAppId),
    this.sTag = t.readString(1, !1, this.sTag)
};

DM.SendMessageFormat = function() {
    this.iSenceType = 0,
    this.lFormatId = 0
};
DM.SendMessageFormat.prototype._clone = function() {
    return new DM.SendMessageFormat
};
DM.SendMessageFormat.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.SendMessageFormat.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.SendMessageFormat.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iSenceType),
    t.writeInt64(1, this.lFormatId)
};
DM.SendMessageFormat.prototype.readFrom = function(t) {
    this.iSenceType = t.readInt32(0, !1, this.iSenceType),
    this.lFormatId = t.readInt64(1, !1, this.lFormatId)
};

DM.UidNickName = function() {
    this.lUid = 0,
    this.sNickName = ""
};
DM.UidNickName.prototype._clone = function() {
    return new DM.UidNickName
};
DM.UidNickName.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.UidNickName.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.UidNickName.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lUid),
    t.writeString(1, this.sNickName)
};
DM.UidNickName.prototype.readFrom = function(t) {
    this.lUid = t.readInt64(0, !1, this.lUid),
    this.sNickName = t.readString(1, !1, this.sNickName)
};

DM.SenderInfo = function() {
    this.lUid = 0,
    this.lImid = 0,
    this.sNickName = "",
    this.iGender = 0,
    this.sAvatarUrl = "",
    this.iNobleLevel = 0,
    this.tNobleLevelInfo = new DM.NobleLevelInfo,
    this.sGuid = "",
    this.sHuYaUA = ""
};
DM.SenderInfo.prototype._clone = function() {
    return new DM.SenderInfo
};
DM.SenderInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.SenderInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.SenderInfo.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lUid),
    t.writeInt64(1, this.lImid),
    t.writeString(2, this.sNickName),
    t.writeInt32(3, this.iGender),
    t.writeString(4, this.sAvatarUrl),
    t.writeInt32(5, this.iNobleLevel),
    t.writeStruct(6, this.tNobleLevelInfo),
    t.writeString(7, this.sGuid),
    t.writeString(8, this.sHuYaUA)
};
DM.SenderInfo.prototype.readFrom = function(t) {
    this.lUid = t.readInt64(0, !1, this.lUid),
    this.lImid = t.readInt64(1, !1, this.lImid),
    this.sNickName = t.readString(2, !1, this.sNickName),
    this.iGender = t.readInt32(3, !1, this.iGender),
    this.sAvatarUrl = t.readString(4, !1, this.sAvatarUrl),
    this.iNobleLevel = t.readInt32(5, !1, this.iNobleLevel),
    this.tNobleLevelInfo = t.readStruct(6, !1, this.tNobleLevelInfo),
    this.sGuid = t.readString(7, !1, this.sGuid),
    this.sHuYaUA = t.readString(8, !1, this.sHuYaUA)
};

DM.ContentFormat = function() {
    this.iFontColor = -1,
    this.iFontSize = 4,
    this.iPopupStyle = 0,
    this.iNickNameFontColor = -1,
    this.iDarkFontColor = -1,
    this.iDarkNickNameFontColor = -1
};
DM.ContentFormat.prototype._clone = function() {
    return new DM.ContentFormat
};
DM.ContentFormat.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.ContentFormat.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.ContentFormat.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iFontColor),
    t.writeInt32(1, this.iFontSize),
    t.writeInt32(2, this.iPopupStyle),
    t.writeInt32(3, this.iNickNameFontColor),
    t.writeInt32(4, this.iDarkFontColor),
    t.writeInt32(5, this.iDarkNickNameFontColor)
};
DM.ContentFormat.prototype.readFrom = function(t) {
    this.iFontColor = t.readInt32(0, !1, this.iFontColor),
    this.iFontSize = t.readInt32(1, !1, this.iFontSize),
    this.iPopupStyle = t.readInt32(2, !1, this.iPopupStyle),
    this.iNickNameFontColor = t.readInt32(3, !1, this.iNickNameFontColor),
    this.iDarkFontColor = t.readInt32(4, !1, this.iDarkFontColor),
    this.iDarkNickNameFontColor = t.readInt32(5, !1, this.iDarkNickNameFontColor)
};

DM.BulletFormat = function() {
    this.iFontColor = -1,
    this.iFontSize = 4,
    this.iTextSpeed = 0,
    this.iTransitionType = 1,
    this.iPopupStyle = 0,
    this.tBorderGroundFormat = new DM.BulletBorderGroundFormat,
    this.vGraduatedColor = new Taf.Vector(new Taf.INT32),
    this.iAvatarFlag = 0,
    this.iAvatarTerminalFlag = -1
};
DM.BulletFormat.prototype._clone = function() {
    return new DM.BulletFormat
};
DM.BulletFormat.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.BulletFormat.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.BulletFormat.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iFontColor),
    t.writeInt32(1, this.iFontSize),
    t.writeInt32(2, this.iTextSpeed),
    t.writeInt32(3, this.iTransitionType),
    t.writeInt32(4, this.iPopupStyle),
    t.writeStruct(5, this.tBorderGroundFormat),
    t.writeVector(6, this.vGraduatedColor),
    t.writeInt32(7, this.iAvatarFlag),
    t.writeInt32(8, this.iAvatarTerminalFlag)
};
DM.BulletFormat.prototype.readFrom = function(t) {
    this.iFontColor = t.readInt32(0, !1, this.iFontColor),
    this.iFontSize = t.readInt32(1, !1, this.iFontSize),
    this.iTextSpeed = t.readInt32(2, !1, this.iTextSpeed),
    this.iTransitionType = t.readInt32(3, !1, this.iTransitionType),
    this.iPopupStyle = t.readInt32(4, !1, this.iPopupStyle),
    this.tBorderGroundFormat = t.readStruct(5, !1, this.tBorderGroundFormat),
    this.vGraduatedColor = t.readVector(6, !1, this.vGraduatedColor),
    this.iAvatarFlag = t.readInt32(7, !1, this.iAvatarFlag),
    this.iAvatarTerminalFlag = t.readInt32(8, !1, this.iAvatarTerminalFlag)
};

DM.BulletBorderGroundFormat = function() {
    this.iEnableUse = 0,
    this.iBorderThickness = 0,
    this.iBorderColour = -1,
    this.iBorderDiaphaneity = 100,
    this.iGroundColour = -1,
    this.iGroundColourDiaphaneity = 100,
    this.sAvatarDecorationUrl = "",
    this.iFontColor = -1,
    this.iTerminalFlag = -1
};
DM.BulletBorderGroundFormat.prototype._clone = function() {
    return new DM.BulletBorderGroundFormat
};
DM.BulletBorderGroundFormat.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.BulletBorderGroundFormat.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.BulletBorderGroundFormat.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iEnableUse),
    t.writeInt32(1, this.iBorderThickness),
    t.writeInt32(2, this.iBorderColour),
    t.writeInt32(3, this.iBorderDiaphaneity),
    t.writeInt32(4, this.iGroundColour),
    t.writeInt32(5, this.iGroundColourDiaphaneity),
    t.writeString(6, this.sAvatarDecorationUrl),
    t.writeInt32(7, this.iFontColor),
    t.writeInt32(8, this.iTerminalFlag)
};
DM.BulletBorderGroundFormat.prototype.readFrom = function(t) {
    this.iEnableUse = t.readInt32(0, !1, this.iEnableUse),
    this.iBorderThickness = t.readInt32(1, !1, this.iBorderThickness),
    this.iBorderColour = t.readInt32(2, !1, this.iBorderColour),
    this.iBorderDiaphaneity = t.readInt32(3, !1, this.iBorderDiaphaneity),
    this.iGroundColour = t.readInt32(4, !1, this.iGroundColour),
    this.iGroundColourDiaphaneity = t.readInt32(5, !1, this.iGroundColourDiaphaneity),
    this.sAvatarDecorationUrl = t.readString(6, !1, this.sAvatarDecorationUrl),
    this.iFontColor = t.readInt32(7, !1, this.iFontColor),
    this.iTerminalFlag = t.readInt32(8, !1, this.iTerminalFlag)
};

DM.DecorationInfo = function() {
    this.iAppId = 0,
    this.iViewType = 0,
    this.vData = new Taf.BinBuffer,
    this.lSourceId = 0,
    this.iType = 0
};
DM.DecorationInfo.prototype._clone = function() {
    return new DM.DecorationInfo
};
DM.DecorationInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.DecorationInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.DecorationInfo.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iAppId),
    t.writeInt32(1, this.iViewType),
    t.writeBytes(2, this.vData),
    t.writeInt64(3, this.lSourceId),
    t.writeInt32(4, this.iType)
};
DM.DecorationInfo.prototype.readFrom = function(t) {
    this.iAppId = t.readInt32(0, !1, this.iAppId),
    this.iViewType = t.readInt32(1, !1, this.iViewType),
    this.vData = t.readBytes(2, !1, this.vData),
    this.lSourceId = t.readInt64(3, !1, this.lSourceId),
    this.iType = t.readInt32(4, !1, this.iType)
};

DM.NobleLevelInfo = function() {
    this.iNobleLevel = 0,
    this.iAttrType = 0
};
DM.NobleLevelInfo.prototype._clone = function() {
    return new DM.NobleLevelInfo
};
DM.NobleLevelInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
};
DM.NobleLevelInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
};
DM.NobleLevelInfo.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iNobleLevel),
    t.writeInt32(1, this.iAttrType)
};
DM.NobleLevelInfo.prototype.readFrom = function(t) {
    this.iNobleLevel = t.readInt32(0, !1, this.iNobleLevel),
    this.iAttrType = t.readInt32(1, !1, this.iAttrType)
};
