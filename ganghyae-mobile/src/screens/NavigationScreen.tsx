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

import { ArrowLeft, ChevronUp, ChevronDown } from 'lucide-react-native';
import MapView, { Marker, Polyline, PROVIDER_GOOGLE } from 'react-native-maps';
import { useNavigation, useRoute } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../types/navigation';

type NavigationScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'Navigation'>;

export function NavigationScreen() {
  const navigation = useNavigation<NavigationScreenNavigationProp>();
  const route = useRoute<any>();
  const { mode } = route.params;
  const isWheelchairMode = mode === "wheelchair";
  const modeColor = isWheelchairMode ? "#a5cfc9" : "#ffdfa3";
  const modeTextColor = isWheelchairMode ? "#7ab3ab" : "#9a8560";

  const routeCoordinates = [
    { latitude: 33.4530, longitude: 126.5600 },
    { latitude: 33.4530, longitude: 126.5615 },
    { latitude: 33.4548, longitude: 126.5615 },
  ];

  return (
    <SafeAreaView className="flex-1 bg-white">
      <View className="flex-1">
        {/* Map View - Zoomed In */}
        <MapViewComponent
          provider={PROVIDER_GOOGLE}
          className="w-full h-full"
          initialRegion={{
            latitude: 33.4535,
            longitude: 126.5610,
            latitudeDelta: 0.005,
            longitudeDelta: 0.005,
          }}
        >
          <PolylineComponent
            coordinates={routeCoordinates}
            strokeColor={isWheelchairMode ? "#a5cfc9" : "#e8c88a"}
            strokeWidth={8}
          />
          <MarkerComponent coordinate={routeCoordinates[0]} title="현재 위치" />
        </MapViewComponent>

        {/* Top Direction Card */}
        <View className="absolute top-12 left-0 right-0 px-4 z-20">
          <TouchableOpacity
            onPress={() => navigation.goBack()}
            className="w-12 h-12 bg-white/80 rounded-full items-center justify-center shadow-lg mb-4"
          >
            <ArrowLeft size={24} color="#475569" />
          </TouchableOpacity>

          <View className="bg-white/90 rounded-2xl shadow-xl p-4 border border-white/50 flex-row items-center">
            {/* Elevator/Stairs Icon Placeholder */}
            <View className="w-16 h-16 rounded-2xl items-center justify-center mr-4" style={{ backgroundColor: modeColor }}>
              <ChevronUp size={32} color="white" />
            </View>
            <View className="flex-1">
              <Text className="text-sm text-slate-500 font-medium">30m 앞</Text>
              <Text className="text-xl font-bold text-slate-800">엘리베이터 탑승</Text>
              <Text className="text-sm font-semibold mt-1" style={{ color: modeTextColor }}>3층으로 이동하세요</Text>
            </View>
            <View className="items-end">
              <Text className="text-3xl font-bold" style={{ color: modeTextColor }}>30</Text>
              <Text className="text-xs text-slate-500 font-medium">미터</Text>
            </View>
          </View>
        </View>

        {/* Bottom Navigation Stats */}
        <View className="absolute bottom-0 left-0 right-0 p-4 pb-10 z-10">
          <View className="bg-white rounded-3xl shadow-2xl p-5 border border-slate-100">
            {/* Progress Bar */}
            <View className="h-2 bg-slate-100 rounded-full overflow-hidden mb-5">
              <View className="h-full w-1/4" style={{ backgroundColor: modeColor }} />
            </View>

            <View className="flex-row justify-between items-center mb-5">
              <View>
                <Text className="text-xs text-slate-500 font-medium">목적지까지</Text>
                <View className="flex-row items-baseline space-x-2 mt-1">
                  <Text className="text-3xl font-bold text-slate-800">12</Text>
                  <Text className="text-lg text-slate-500 ml-1">분</Text>
                  <Text className="text-xl font-semibold ml-3" style={{ color: modeTextColor }}>900m</Text>
                </View>
                <Text className="text-sm font-semibold mt-1" style={{ color: modeTextColor }}>중앙도서관</Text>
              </View>
              <View className="items-end">
                <Text className="text-xs text-slate-500 font-medium">도착 예정</Text>
                <Text className="text-2xl font-bold text-slate-800">14:32</Text>
              </View>
            </View>

            {/* End Button */}
            <TouchableOpacity
              onPress={() => navigation.navigate('Search')}
              className="w-full py-4 bg-[#B97878] rounded-2xl items-center flex-row justify-center"
            >
              <View className="w-4 h-4 bg-white rounded-sm mr-2" />
              <Text className="text-white font-bold text-lg ml-2">길 안내 종료</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}
