set -e
EXIT_CODE=0

FROM_EMAIL=$SCHOOL_EMAIL
FROM_NAME="0tree"
SMTP_HOST=$SCHOOL_EMAIL_HOST
SMTP_PORT=$SCHOOL_EMAIL_PORT
SMTP_PASSWORD=$SCHOOL_SMTP_PASSWORD

TO_EMAIL=$QQ_EMAIL

echo $FROM_EMAIL
echo $FROM_NAME
echo $SMTP_HOST
echo $SMTP_PORT
echo $SMTP_PASSWORD

MACHINE=$(hostname)
EXPERIMENT_DIR=$(basename "$(pwd)")
EXPERIMENT_NAME="${EXPERIMENT_DIR}"
#MACHINE_IP=$(hostname -I | awk '{print $1}') #ubuntu
MACHINE_IP=$(hostname -i | awk '{print $1}') #archlinux



if [ $EXIT_CODE -eq 0 ]; then
    STATUS="成功 ✅"
    STATUS_COLOR="#27ae60"
    STATUS_EMOJI="🎉"
else
    STATUS="失败 ❌"
    STATUS_COLOR="#e74c3c"
    STATUS_EMOJI="😞"
fi

SUBJECT="${MACHINE} 实验完成: $EXPERIMENT_NAME"

HTML_BODY=$(cat << EOF
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.4; color: #333; max-width: 500px; margin: 0 auto;">
    <div style="text-align: center; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border-radius: 8px 8px 0 0;">
        <h1 style="margin: 0; font-size: 24px;">${STATUS_EMOJI} 实验运行完成</h1>
    </div>

    <div style="padding: 20px; background: #f8f9fa; border-radius: 0 0 8px 8px;">
        <div style="background: white; padding: 15px; border-radius: 5px; margin-bottom: 15px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
            <h3 style="margin-top: 0; color: #2c3e50;">📋 实验信息</h3>
            <p><strong>实验名称:</strong> $EXPERIMENT_NAME</p>
            <p><strong>状态:</strong> <span style="color: $STATUS_COLOR; font-weight: bold;">$STATUS</span></p>
            <p><strong>完成时间:</strong> $(date "+%Y-%m-%d %H:%M:%S")</p>
            <p><strong>退出代码:</strong> $EXIT_CODE</p>
        </div>

        <div style="background: white; padding: 15px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
            <h3 style="margin-top: 0; color: #2c3e50;">🖥️ 系统状态</h3>
            <p><strong>运行目录:</strong> $(pwd)</p>
            <p><strong>主机名:</strong> $(hostname)</p>
            <p><strong>用户:</strong> $(whoami)</p>
            <p><strong>IP地址:</strong> $MACHINE_IP</p>
        </div>
    </div>
</body>
</html>
EOF
)
MAIL_CONTENT=$(cat << EOF
From: $FROM_NAME <$FROM_EMAIL>
To: $TO_EMAIL
Subject: $SUBJECT
Content-Type: text/html; charset="UTF-8"
MIME-Version: 1.0

$HTML_BODY
EOF
)

MAIL_FILE=$(mktemp)
echo $MAIL_CONTENT
echo $MAIL_FILE
echo "$MAIL_CONTENT" > "$MAIL_FILE"

echo "发送实验完成通知..."
if echo | mutt \
    -e "set content_type=text/html" \
    -e "set from='$FROM_EMAIL'" \
    -e "set realname='$FROM_NAME'" \
    -e "set smtp_url='smtps://$FROM_EMAIL:$SMTP_PASSWORD@$SMTP_HOST:$SMTP_PORT/'" \
    -e "set ssl_force_tls=yes" \
	-e "set copy=no" \
    -s "$SUBJECT" \
    -- "$TO_EMAIL" < "$MAIL_FILE"; then
    echo "通知发送成功!"
else
    echo "通知发送失败!"
fi

rm -f "$MAIL_FILE"
