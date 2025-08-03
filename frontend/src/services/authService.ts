import {
  CognitoUserPool,
  CognitoUser,
  AuthenticationDetails,
  CognitoUserAttribute,
  CognitoUserSession
} from 'amazon-cognito-identity-js';

// Cognito設定
const poolData = {
  UserPoolId: import.meta.env.VITE_USER_POOL_ID || 'us-east-1_dummy',
  ClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID || 'dummy'
};

const userPool = new CognitoUserPool(poolData);

// ユーザー情報の型定義（exportを追加）
export interface AuthUser {
  username: string;
  email: string;
  name?: string;
  role?: string;
}

export interface SignUpData {
  username: string;
  password: string;
  email: string;
  name?: string;
}

export interface SignInData {
  username: string;
  password: string;
}

// 認証サービスクラス
export class AuthService {
  
  // 現在のユーザーセッションを取得
  static getCurrentUser(): Promise<AuthUser | null> {
    return new Promise((resolve) => {
      const cognitoUser = userPool.getCurrentUser();
      
      if (!cognitoUser) {
        resolve(null);
        return;
      }

      cognitoUser.getSession((err: any, session: CognitoUserSession | null) => {
        if (err || !session || !session.isValid()) {
          resolve(null);
          return;
        }

        cognitoUser.getUserAttributes((err, attributes) => {
          if (err) {
            resolve(null);
            return;
          }

          const email = attributes?.find(attr => attr.getName() === 'email')?.getValue() || '';
          const name = attributes?.find(attr => attr.getName() === 'name')?.getValue() || '';
          const role = attributes?.find(attr => attr.getName() === 'custom:role')?.getValue() || 'user';

          resolve({
            username: cognitoUser.getUsername(),
            email,
            name,
            role
          });
        });
      });
    });
  }

  // JWTトークンを取得
  static getAccessToken(): Promise<string | null> {
    return new Promise((resolve) => {
      const cognitoUser = userPool.getCurrentUser();
      
      if (!cognitoUser) {
        resolve(null);
        return;
      }

      cognitoUser.getSession((err: any, session: CognitoUserSession | null) => {
        if (err || !session || !session.isValid()) {
          resolve(null);
          return;
        }

        resolve(session.getAccessToken().getJwtToken());
      });
    });
  }

  // サインアップ
  static signUp(data: SignUpData): Promise<{ success: boolean; message: string; needsConfirmation?: boolean }> {
    return new Promise((resolve) => {
      const attributeList = [
        new CognitoUserAttribute({
          Name: 'email',
          Value: data.email
        })
      ];

      if (data.name) {
        attributeList.push(new CognitoUserAttribute({
          Name: 'name',
          Value: data.name
        }));
      }

      userPool.signUp(
        data.username,
        data.password,
        attributeList,
        [],
        (err, result) => {
          if (err) {
            resolve({
              success: false,
              message: err.message || 'サインアップに失敗しました'
            });
            return;
          }

          resolve({
            success: true,
            message: 'サインアップが完了しました。メールで認証コードを確認してください。',
            needsConfirmation: !result?.user.getUsername()
          });
        }
      );
    });
  }

  // メール認証コードの確認
  static confirmSignUp(username: string, code: string): Promise<{ success: boolean; message: string }> {
    return new Promise((resolve) => {
      const cognitoUser = new CognitoUser({
        Username: username,
        Pool: userPool
      });

      cognitoUser.confirmRegistration(code, true, (err) => {
        if (err) {
          resolve({
            success: false,
            message: err.message || '認証コードの確認に失敗しました'
          });
          return;
        }

        resolve({
          success: true,
          message: 'メール認証が完了しました。ログインできます。'
        });
      });
    });
  }

  // サインイン
  static signIn(data: SignInData): Promise<{ success: boolean; message: string; user?: AuthUser; needsNewPassword?: boolean }> {
    return new Promise((resolve) => {
      const authenticationDetails = new AuthenticationDetails({
        Username: data.username,
        Password: data.password
      });

      const cognitoUser = new CognitoUser({
        Username: data.username,
        Pool: userPool
      });

      cognitoUser.authenticateUser(authenticationDetails, {
        onSuccess: (session) => {
          cognitoUser.getUserAttributes((err, attributes) => {
            if (err) {
              resolve({
                success: false,
                message: 'ユーザー情報の取得に失敗しました'
              });
              return;
            }

            const email = attributes?.find(attr => attr.getName() === 'email')?.getValue() || '';
            const name = attributes?.find(attr => attr.getName() === 'name')?.getValue() || '';
            const role = attributes?.find(attr => attr.getName() === 'custom:role')?.getValue() || 'user';

            resolve({
              success: true,
              message: 'ログインに成功しました',
              user: {
                username: cognitoUser.getUsername(),
                email,
                name,
                role
              }
            });
          });
        },
        onFailure: (err) => {
          resolve({
            success: false,
            message: err.message || 'ログインに失敗しました'
          });
        },
        newPasswordRequired: (userAttributes) => {
          resolve({
            success: false,
            message: '新しいパスワードの設定が必要です',
            needsNewPassword: true
          });
        }
      });
    });
  }

  // パスワード変更（初回ログイン時）
  static completeNewPasswordChallenge(username: string, newPassword: string): Promise<{ success: boolean; message: string }> {
    return new Promise((resolve) => {
      const cognitoUser = new CognitoUser({
        Username: username,
        Pool: userPool
      });

      // この実装は簡略化されています。実際にはセッション管理が必要です。
      resolve({
        success: false,
        message: 'この機能は実装中です。管理者にお問い合わせください。'
      });
    });
  }

  // パスワードリセット
  static forgotPassword(username: string): Promise<{ success: boolean; message: string }> {
    return new Promise((resolve) => {
      const cognitoUser = new CognitoUser({
        Username: username,
        Pool: userPool
      });

      cognitoUser.forgotPassword({
        onSuccess: () => {
          resolve({
            success: true,
            message: 'パスワードリセット用のコードをメールで送信しました'
          });
        },
        onFailure: (err) => {
          resolve({
            success: false,
            message: err.message || 'パスワードリセットに失敗しました'
          });
        }
      });
    });
  }

  // パスワードリセット確認
  static confirmPassword(username: string, code: string, newPassword: string): Promise<{ success: boolean; message: string }> {
    return new Promise((resolve) => {
      const cognitoUser = new CognitoUser({
        Username: username,
        Pool: userPool
      });

      cognitoUser.confirmPassword(code, newPassword, {
        onSuccess: () => {
          resolve({
            success: true,
            message: 'パスワードが正常に変更されました'
          });
        },
        onFailure: (err) => {
          resolve({
            success: false,
            message: err.message || 'パスワード変更に失敗しました'
          });
        }
      });
    });
  }

  // サインアウト
  static signOut(): Promise<void> {
    return new Promise((resolve) => {
      const cognitoUser = userPool.getCurrentUser();
      
      if (cognitoUser) {
        cognitoUser.signOut();
      }
      
      resolve();
    });
  }

  // 認証状態の確認
  static isAuthenticated(): Promise<boolean> {
    return new Promise((resolve) => {
      const cognitoUser = userPool.getCurrentUser();
      
      if (!cognitoUser) {
        resolve(false);
        return;
      }

      cognitoUser.getSession((err: any, session: CognitoUserSession | null) => {
        resolve(!err && session !== null && session.isValid());
      });
    });
  }
}
