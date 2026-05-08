import React from 'react';
import { View, Text, TouchableOpacity, SafeAreaView, Platform } from 'react-native';

// Use placeholders for MapView on web
const MapViewMock = ({ children, ...props }: any) => (
  <View {...props} style={[props.style, { backgroundColor: '#e2e8f0', justifyContent: 'center', alignItems: 'center' }]}>
    <Text className="text-slate-500 font-medium">지도는 모바일 기기에서 확인 가능합니다</Text>
    {children}
  </View>
);
const MarkerMock = () => null;
const PolylineMock = () => null;

const MapViewComponent = Platform.OS === 'web' ? MapViewMock : MapView;
const MarkerComponent = Platform.OS === 'web' ? MarkerMock : Marker;
const PolylineComponent = Platform.OS === 'web' ? PolylineMock : Polyline;

import { ArrowLeft, Clock, Route, CheckCircle2, Accessibility, AlertTriangle } from 'lucide-react-native';
import MapView, { Marker, Polyline, PROVIDER_GOOGLE } from 'react-native-maps';
import { useNavigation, useRoute } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../types/navigation';

type RouteScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'Route'>;

export function RouteScreen() {
  const navigation = useNavigation<RouteScreenNavigationProp>();
  const route = useRoute<any>();
  const { mode } = route.params;
  const isWheelchairMode = mode === "wheelchair";

  const routeCoordinates = [
    { latitude: 33.4520, longitude: 126.5600 },
    { latitude: 33.4530, longitude: 126.5600 },
    { latitude: 33.4530, longitude: 126.5615 },
    { latitude: 33.4548, longitude: 126.5615 },
  ];

  return (
    <SafeAreaView className="flex-1 bg-white">
      <View className="flex-1">
        {/* Map View with Route */}
        <MapViewComponent
          provider={PROVIDER_GOOGLE}
          className="w-full h-full"
          initialRegion={{
            latitude: 33.4535,
            longitude: 126.5610,
            latitudeDelta: 0.01,
            longitudeDelta: 0.01,
          }}
        >
          <MarkerComponent coordinate={routeCoordinates[0]} pinColor="#D4A5A5" title="출발" />
          <MarkerComponent coordinate={routeCoordinates[routeCoordinates.length - 1]} pinColor="#A5C4D4" title="도착" />
          <PolylineComponent
            coordinates={routeCoordinates}
            strokeColor={isWheelchairMode ? "#a5cfc9" : "#e8c88a"}
            strokeWidth={6}
          />
        </MapViewComponent>

        {/* Back Button */}
        <TouchableOpacity
          onPress={() => navigation.goBack()}
          className="absolute top-12 left-4 z-20 w-12 h-12 bg-white/80 rounded-full items-center justify-center shadow-lg"
        >
          <ArrowLeft size={24} color="#475569" />
        </TouchableOpacity>

        {/* Mode Indicator */}
        <View className="absolute top-12 right-4 z-20">
          <View className={`px-4 py-2 rounded-full flex-row items-center space-x-2 bg-white/80 shadow-lg border ${isWheelchairMode ? 'border-[#a5cfc9]' : 'border-[#e8c88a]'}`}>
            <Accessibility size={16} color={isWheelchairMode ? "#7ab3ab" : "#9a8560"} />
            <Text className={`text-sm font-bold ml-2 ${isWheelchairMode ? "text-[#7ab3ab]" : "text-[#9a8560]"}`}>
              {isWheelchairMode ? "휠체어 모드" : "일반 모드"}
            </Text>
          </View>
        </View>

        {/* Bottom Info Card */}
        <View className="absolute bottom-0 left-0 right-0 p-4 pb-10">
          <View className="bg-white rounded-3xl shadow-2xl overflow-hidden border border-slate-100">
            {/* Destination Header */}
            <View className="p-5 border-b border-slate-100 flex-row justify-between items-center">
              <View>
                <Text className="text-xs text-slate-500 mb-1 font-medium">목적지</Text>
                <Text className="text-xl font-bold text-slate-800">제주대학교 중앙도서관</Text>
              </View>
              <View className={`w-12 h-12 rounded-xl items-center justify-center ${isWheelchairMode ? "bg-[#a5cfc9]" : "bg-[#e8c88a]"}`}>
                <MapPin size={24} color="white" />
              </View>
            </View>

            {/* Route Info Stats */}
            <View className="p-5 flex-row border-b border-slate-100">
              <View className="flex-1 flex-row items-center space-x-3">
                <View className={`w-10 h-10 rounded-xl items-center justify-center ${isWheelchairMode ? "bg-[#a5cfc9]/20" : "bg-[#ffdfa3]/30"}`}>
                  <Clock size={20} color={isWheelchairMode ? "#7ab3ab" : "#9a8560"} />
                </View>
                <View className="ml-3">
                  <Text className="text-xs text-slate-500 font-medium">예상 시간</Text>
                  <Text className="text-lg font-bold text-slate-800">15분</Text>
                </View>
              </View>
              <View className="flex-1 flex-row items-center space-x-3">
                <View className={`w-10 h-10 rounded-xl items-center justify-center ${isWheelchairMode ? "bg-[#a5cfc9]/20" : "bg-[#ffdfa3]/30"}`}>
                  <Route size={20} color={isWheelchairMode ? "#7ab3ab" : "#9a8560"} />
                </View>
                <View className="ml-3">
                  <Text className="text-xs text-slate-500 font-medium">총 거리</Text>
                  <Text className="text-lg font-bold text-slate-800">1.2km</Text>
                </View>
              </View>
            </View>

            {/* Benefits Banner */}
            {isWheelchairMode ? (
              <View className="p-5 bg-[#a5cfc9]/10">
                <View className="flex-row items-start space-x-3">
                  <CheckCircle2 size={24} color="#7ab3ab" />
                  <View className="ml-3 flex-1">
                    <Text className="text-base font-bold text-[#7ab3ab]">보행 약자를 위한 안전 경로</Text>
                    <Text className="text-sm text-slate-600 mt-1">계단을 2번 덜 지나는 쾌적한 경로입니다.</Text>
                  </View>
                </View>
              </View>
            ) : (
              <View className="p-5 bg-amber-50">
                <View className="flex-row items-start space-x-3">
                  <AlertTriangle size={24} color="#B97878" />
                  <View className="ml-3 flex-1">
                    <Text className="text-base font-bold text-[#B97878]">계단 포함 경로</Text>
                    <Text className="text-sm text-slate-600 mt-1">이 경로에는 계단이 3곳 포함되어 있습니다.</Text>
                  </View>
                </View>
              </View>
            )}

            {/* Action Button */}
            <View className="p-5">
              <TouchableOpacity
                onPress={() => navigation.navigate('Navigation', { mode })}
                className={`w-full py-4 rounded-2xl items-center ${isWheelchairMode ? 'bg-[#a5cfc9]' : 'bg-[#e8c88a]'}`}
              >
                <Text className={`text-white font-bold text-lg ${!isWheelchairMode && 'text-[#6b5a3a]'}`}>
                  {isWheelchairMode ? "안전 경로 안내 시작" : "일반 모드 안내 시작"}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}
