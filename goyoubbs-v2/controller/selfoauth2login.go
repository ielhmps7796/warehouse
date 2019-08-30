package controller

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"goyoubbs/model"
	"goyoubbs/util"
	"html/template"
	"io/ioutil"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/rs/xid"
	"github.com/youdb"
	"golang.org/x/oauth2"
	"golang.org/x/randx"
)

var tokenUserWelcome = template.Must(template.New("").Parse(`<html>
<body>
<h1>Welcome to the B502</h1>
<p>点击下方链接以B502账号进行登录</p>
<p><a href="{{.URL}}">B502</a></p>
</body>
</html>`))

var tokenUserError = template.Must(template.New("").Parse(`<html>
<body>
<h1>An error occurred</h1>
<h2>{{ .Name }}</h2>
<p>{{ .Description }}</p>
<p>{{ .Hint }}</p>
<p>{{ .Debug }}</p>
</body>
</html>`))

var tokenUserResult = template.Must(template.New("").Parse(`<html>
<html>
<head></head>
<body>
<ul>
    <li>Access Token: <code>{{ .AccessToken }}</code></li>
    <li>Refresh Token: <code>{{ .RefreshToken }}</code></li>
    <li>Expires in: <code>{{ .Expiry }}</code></li>
    <li>ID Token: <code>{{ .IDToken }}</code></li>
</ul>
</body>
</html>`))

var conf oauth2.Config
var state []rune
var ctx = context.Background()

type content struct {
	Sid string `json:"sid"`
	Sub string `json:"sub"`
}

type ed struct {
	Name        string
	Description string
	Hint        string
	Debug       string
}

func (h *BaseHandler) SelfOauth2Handler(w http.ResponseWriter, r *http.Request) {
	ctx = context.WithValue(context.Background(), oauth2.HTTPClient, &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}})

	conf = oauth2.Config{
		ClientID:     "B502",
		ClientSecret: "502password",
		Endpoint: oauth2.Endpoint{
			//TokenURL: "https://ory-hydra-example--hydra:4444/oauth2/token",
			TokenURL: "https://192.168.31.106:9000/oauth2/token",
			AuthURL:  "https://192.168.31.106:9000/oauth2/auth",
		},
		RedirectURL: "https://192.168.31.150:8082/callback", //自己的ip
		Scopes:      []string{"openid", "offline", "photos.read"},
	}
	var err error
	state, err = randx.RuneSequence(24, randx.AlphaLower)
	if err != nil {
		fmt.Println(err)
	}
	nonce, err := randx.RuneSequence(24, randx.AlphaLower)
	if err != nil {
		fmt.Println(err)
	}

	authCodeURL := conf.AuthCodeURL(
		string(state),
		oauth2.SetAuthURLParam("audience", ""),
		oauth2.SetAuthURLParam("nonce", string(nonce)),
		oauth2.SetAuthURLParam("prompt", ""),
		oauth2.SetAuthURLParam("max_age", strconv.Itoa(0)),
	)
	//fmt.Printf("&&&&& %s\n", string(state))
	//_ = tokenUserWelcome.Execute(w, &struct{ URL string }{URL: authCodeURL})
	http.Redirect(w, r, authCodeURL, http.StatusSeeOther)

}

func (h *BaseHandler) SelfOauth2Callback(w http.ResponseWriter, r *http.Request) {
	if len(r.URL.Query().Get("error")) > 0 {
		fmt.Printf("Got error: %s\n", r.URL.Query().Get("error_description"))

		w.WriteHeader(http.StatusInternalServerError)
		_ = tokenUserError.Execute(w, &ed{
			Name:        r.URL.Query().Get("error"),
			Description: r.URL.Query().Get("error_description"),
			Hint:        r.URL.Query().Get("error_hint"),
			Debug:       r.URL.Query().Get("error_debug"),
		})
		return
	}
	if r.URL.Query().Get("state") != string(state) {
		fmt.Printf("States do not match. Expected %s, got %s\n", string(state), r.URL.Query().Get("state"))

		w.WriteHeader(http.StatusInternalServerError)
		_ = tokenUserError.Execute(w, &ed{
			Name:        "States do not match",
			Description: "Expected state " + string(state) + " but got " + r.URL.Query().Get("state"),
		})
		//	go shutdown()
		return
	}

	code := r.URL.Query().Get("code")
	token, err := conf.Exchange(ctx, code)
	if err != nil {
		fmt.Printf("Unable to exchange code for token: %s\n", err)

		w.WriteHeader(http.StatusInternalServerError)
		_ = tokenUserError.Execute(w, &ed{
			Name: err.Error(),
		})
		//	go shutdown()
		return
	}

	/*idt := token.Extra("id_token")
	fmt.Printf("Access Token:\n\t%s\n", token.AccessToken)
	fmt.Printf("Refresh Token:\n\t%s\n", token.RefreshToken)
	fmt.Printf("Expires in:\n\t%s\n", token.Expiry.Format(time.RFC1123))
	fmt.Printf("ID Token:\n\t%v\n\n", idt)

	_ = tokenUserResult.Execute(w, struct {
		AccessToken  string
		RefreshToken string
		Expiry       string
		IDToken      string
	}{
		AccessToken:  token.AccessToken,
		RefreshToken: token.RefreshToken,
		Expiry:       fmt.Sprintf("%s", token.Expiry.Format(time.RFC1123)),
		IDToken:      fmt.Sprintf("%v", idt),
	})*/

	headers := map[string][]string{
		"Accept":        []string{"application/json"},
		"Authorization": []string{"Bearer " + token.AccessToken},
	}

	//var body []byte
	//body = nil
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	req, err := http.NewRequest("GET", "https://192.168.31.106:9000/userinfo", nil)
	if err != nil {
		fmt.Println("**" + err.Error())
	}
	req.Header = headers
	client := &http.Client{Transport: tr}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Println("***" + err.Error())
	}
	defer resp.Body.Close()
	contents, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Println("****" + err.Error())
	}
	//fmt.Printf("Content: %s\n", contents)
	var structcontent content
	json.Unmarshal([]byte(contents), &structcontent)
	fmt.Println(structcontent.Sub)
	//fmt.Println(structcontent.Sid)
	//

	selfUserID := structcontent.Sub

	timeStamp := uint64(time.Now().UTC().Unix())

	db := h.App.Db
	rs := db.Hget("oauth_self", []byte(selfUserID))
	if rs.State == "ok" {
		fmt.Println("测试一下sid")
		// login
		obj := model.QQ{}
		json.Unmarshal(rs.Data[0], &obj)
		uobj, err := model.UserGetById(db, obj.Uid)
		if err != nil {
			w.Write([]byte(err.Error()))
			return
		}
		sessionid := xid.New().String()
		uobj.LastLoginTime = timeStamp
		uobj.Session = sessionid
		jb, _ := json.Marshal(uobj)
		db.Hset("user", youdb.I2b(uobj.Id), jb)
		h.SetCookie(w, "SessionID", strconv.FormatUint(uobj.Id, 10)+":"+sessionid, 365)
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}

	/*profile, err := weibo.GetUserInfo(token.AccessToken, wbUserID)
	if err != nil {
		w.Write([]byte(err.Error()))
		return
	}*/

	// register

	siteCf := h.App.Cf.Site
	if siteCf.CloseReg {
		w.Write([]byte(`{"retcode":400,"retmsg":"stop to new register"}`))
		return
	}

	name := util.RemoveCharacter(structcontent.Sub)
	name = strings.TrimSpace(strings.Replace(name, " ", "", -1))
	if len(name) == 0 {
		name = "ldap"
	}
	nameLow := strings.ToLower(name)
	i := 1
	for {
		if db.Hget("user_name2uid", []byte(nameLow)).State == "ok" {
			i++
			nameLow = name + strconv.Itoa(i)
		} else {
			name = nameLow
			break
		}
	}

	userId, _ := db.HnextSequence("user")
	flag := 5
	if siteCf.RegReview {
		flag = 1
	}
	if userId == 1 {
		flag = 99
	}

	gender := "female"
	/*if profile.Gender == "m" {
		gender = "male"
	}*/

	uobj := model.User{
		Id:   userId,
		Name: name,
		//About:         profile.Description,
		//Url:           profile.URL,
		Gender: gender,
		Flag:   flag,
		//RegTime:       timeStamp,
		//LastLoginTime: timeStamp,
		Session: xid.New().String(),
	}

	uidStr := strconv.FormatUint(userId, 10)
	savePath := "E:/GoWorks/src/goyoubbs/static/avatar/" + uidStr + ".jpg"
	//err = util.FetchAvatar(profile.Avatar, savePath, r.UserAgent())
	//if err != nil {
	err = util.GenerateAvatar(gender, name, 73, 73, savePath)
	//}
	if err != nil {
		uobj.Avatar = "0"
	} else {
		uobj.Avatar = uidStr
	}

	jb, _ := json.Marshal(uobj)
	db.Hset("user", youdb.I2b(uobj.Id), jb)
	db.Hset("user_name2uid", []byte(nameLow), youdb.I2b(userId))
	db.Hset("user_flag:"+strconv.Itoa(flag), youdb.I2b(uobj.Id), []byte(""))

	obj := model.WeiBo{
		Uid:    userId,
		Name:   name,
		Openid: selfUserID,
	}
	jb, _ = json.Marshal(obj)
	db.Hset("oauth_self", []byte(selfUserID), jb)

	h.SetCookie(w, "SessionID", strconv.FormatUint(uobj.Id, 10)+":"+uobj.Session, 365)
	http.Redirect(w, r, "/", http.StatusSeeOther)

}
