var express = require('express');

var ldap =  require("ldapjs");

var router = express.Router();
var url = require('url');
var hydra = require('../services/hydra')

// Sets up csrf protection
var csrf = require('csurf');
var csrfProtection = csrf({ cookie: true });


router.get('/', csrfProtection, function (req, res, next) {
  // Parses the URL query
  var query = url.parse(req.url, true).query

  // The challenge is used to fetch information about the login request from ORY Hydra.
  var challenge = query.login_challenge;

  hydra.getLoginRequest(challenge)
  // This will be called if the HTTP request was successful
    .then(function (response) {
      // If hydra was already able to authenticate the user, skip will be true and we do not need to re-authenticate
      // the user.
      if (response.skip) {
        // You can apply logic here, for example update the number of times the user logged in.
        // ...

        // Now it's time to grant the login request. You could also deny the request if something went terribly wrong
        // (e.g. your arch-enemy logging in...)
        return hydra.acceptLoginRequest(challenge, {
          // All we need to do is to confirm that we indeed want to log in the user.
          subject: response.subject
        }).then(function (response) {
          // All we need to do now is to redirect the user back to hydra!
          res.redirect(response.redirect_to);
        });
      }

      // If authentication can't be skipped we MUST show the login UI.
      res.render('login', {
        csrfToken: req.csrfToken(),
        challenge: challenge,
      });
    })
    // This will handle any error that happens when making HTTP calls to hydra
    .catch(function (error) {
      next(error);
    });
});

router.post('/', csrfProtection, function (req, res, next) {
  // The challenge is now a hidden input field, so let's take it from the request body instead
  var challenge = req.body.challenge;

  /////#########################################################



//创建LDAP client，把服务器url传入
var client = ldap.createClient({
  url: 'ldap://192.168.31.106:389'
});

var queryname = req.body.email
var querypassword = req.body.password
var temp = 'uid='+queryname
//创建LDAP查询选项
//filter的作用就是相当于SQL的条件
var opts = {
  filter: '('+temp+')', //查询条件过滤器，查找uid=kxh的用户节点
  scope: 'sub',        //查询范围
  timeLimit: 500       //查询超时
};

//将client绑定LDAP Server
//第一个参数：是用户，必须是从根节点到用户节点的全路径
//第二个参数：用户密码
client.bind('cn=admin,dc=b502,dc=com', '502password', function (err, res1) {

    //开始查询
    //第一个参数：查询基础路径，代表在查询用户信心将在这个路径下进行，这个路径是由根节开始
    //第二个参数：查询选项
    client.search('dc=b502,dc=com', opts, function (err, res2) {

        //查询结果事件响应
        res2.on('searchEntry', function (entry) {
            
            //获取查询的对象
            var user = entry.object;
            var userText = JSON.stringify(user,null,2);
            console.log(user.dn)
            console.log(userText);

	    global.userid = user.uid;
	    console.log("******"+global.userid)

            /////#####################密码验证           
            var realPasswd = user.userPassword;
            // 引入crypto模块
            const crypto = require('crypto');
            
            // 获取加密算法
            const reg = /^\{(\w+)\}/;
            var temp = reg.exec(realPasswd);
            if(null != temp) {
                /* 加密密码 */
                // 加密算法
                var hash_type = temp[1];
                var raw = realPasswd.replace(temp[0], "");
               // console.log(raw);
                // 将加密后的字符串base64解码
                // 注意，不要转为字符串，因为salt长度为4个字节，但转为字符串后长度不一定为4
                var decoded_64 = new Buffer.from(raw, 'base64')
            
                // 根据加密算法选择
                var cipher = "sha1";
                switch(hash_type) {
		    case "SHA":
			cipher = "sha1";
			break;
                    case "SSHA":
                        cipher = "sha1";
                        break;
                    case "SSHA256":
                        cipher = "sha256";
                        break;
                    case "SSHA384":
                        cipher = "sha384";
                        break;
                    case "SSHA512":
                        cipher = "sha512";
                        break;
            
                    default:
                        cipher = "NORMAOL_TYPE";
                        break;
                }
            
                var passwd = req.body.password
                var input_data = passwd;
                if("NORMAOL_TYPE" != cipher) {
                    // 使用buffer的slice方法
                    var C = decoded_64.slice(0, 20);
            
                    // 20位之后的为随机明文 salt(盐)，长度为4位
                    var salt = decoded_64.slice(20, decoded_64.length);
                    input_data = Buffer.concat([new Buffer.from(passwd), salt]);
            
                    // 加盐干扰：计算 C_input = SHA1(input+salt)
                    var C_input = crypto.createHash(cipher)
                    .update(input_data)
                    .digest('base64');
                    C_input = new Buffer.from(C_input, 'base64')
                }
                else {
                    /* 普通哈希 */
                    switch(hash_type) {
                        case "SHA":
                            cipher = "sha1";
                            break;
                        case "SHA256":
                            cipher = "sha256";
                            break;
                        case "SHA384":
                            cipher = "sha384";
                            break;
                        case "SHA512":
                            cipher = "sha512";
                            break;
                    }
                }
                // 加盐干扰：计算 C_input = SHA1(input+salt)
                // 普通哈希：计算 C_input = SHA1(input)
                var C_input = crypto.createHash(cipher)
                                   .update(input_data)
                                    .digest('base64')
                                    .toString('utf8');
                C_input = new Buffer.from(C_input, 'base64').toString('utf8');
            
                // 如果 C == C_input，说明密码正确（即 A == input）
                // C <> C_input
                if(C == C_input){
                  console.log("密码正确")
                }
                else{
                  console.log("密码错误")
                }
                if (C != C_input) {
                  // Looks like the user provided invalid credentials, let's show the ui again...
              
                  res.render('login', {
                    csrfToken: req.csrfToken(),
              
                    challenge: challenge,
              
                    error: 'The username / password combination is not correct'
                  });
                  return;
                }
            }
            else {
                // 明文密码
                console.log("明文密码")
            }
/////##################密码验证部分结束

            
        });
        
        res2.on('searchReference', function(referral) {
            console.log('referral: ' + referral.uris.join());
        });    
        
        //查询错误事件
        res2.on('error', function(err) {
            console.error('error: ' + err.message);
            //unbind操作，必须要做
            client.unbind();
        });
        
        //查询结束
        res2.on('end', function(result) {
        //    console.log("查询结束"+result.id)
        //    console.log(result.messageID)
            console.log('search status: ' + result.status);
            //unbind操作，必须要做
            client.unbind();
        });        
        
     console.log("%%%%%%%%"+global.userid);
    });
    
  });

/////#########################################################

  // Let's check if the user provided valid credentials. Of course, you'd use a database or some third-party service
  // for this!
  

  // Seems like the user authenticated! Let's tell hydra...
  hydra.acceptLoginRequest(challenge, {
    // Subject is an alias for user ID. A subject can be a random string, a UUID, an email address, ....
    subject: req.body.email,

    // This tells hydra to remember the browser and automatically authenticate the user in future requests. This will
    // set the "skip" parameter in the other route to true on subsequent requests!
    remember: Boolean(req.body.remember),

    // When the session expires, in seconds. Set this to 0 so it will never expire.
    remember_for: 3600,

    // Sets which "level" (e.g. 2-factor authentication) of authentication the user has. The value is really arbitrary
    // and optional. In the context of OpenID Connect, a value of 0 indicates the lowest authorization level.
    // acr: '0',
  })
    .then(function (response) {
      // All we need to do now is to redirect the user back to hydra!
      res.redirect(response.redirect_to);
    })
    // This will handle any error that happens when making HTTP calls to hydra
    .catch(function (error) {
      next(error);
    });

  // You could also deny the login request which tells hydra that no one authenticated!
  // hydra.rejectLoginRequest(challenge, {
  //   error: 'invalid_request',
  //   error_description: 'The user did something stupid...'
  // })
  //   .then(function (response) {
  //     // All we need to do now is to redirect the browser back to hydra!
  //     res.redirect(response.redirect_to);
  //   })
  //   // This will handle any error that happens when making HTTP calls to hydra
  //   .catch(function (error) {
  //     next(error);
  //   });
});

module.exports = router;
